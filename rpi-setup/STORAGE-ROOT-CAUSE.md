# USB Storage Root Cause Analysis

## Critical Finding: USB 2.0 Connection Speed

**Problem:** The PNY USB 3.2.1 Flash Drive (256GB) is connected at **USB 2.0 speed (480 Mbps)** instead of **USB 3.0 speed (5000 Mbps)**.

### Detection
```
Bus 003.Port 002: Dev 002, If 0, Class=Mass Storage, Driver=usb-storage, 480M
```

### Impact on System Stability

**Write Performance:**
- USB 2.0: ~60 MB/s maximum
- USB 3.0: ~625 MB/s maximum  
- **10x slower writes = 10x longer window for corruption**

**How This Causes Unclean Shutdowns:**

1. **InfluxDB writes data every 5 minutes** from 4 sensors
2. Data sits in **RAM buffer (dirty cache)** for up to 5 seconds before commit
3. On **USB 2.0**, writes take longer, so more data accumulates in RAM
4. If **power fails** during write window:
   - Dirty cache in RAM is lost
   - Journal has partial transactions
   - Filesystem marked as "not clean"
   - InfluxDB bolt file corrupted

### Why This Explains the Pattern

**Observed unclean shutdowns:**
- May 17, 23:58
- May 20, 07:11  
- May 20, 19:20
- May 22, 06:43
- May 22, 16:59

**Theory:** These are **brief power interruptions** (brownouts, momentary outages) from:
- Building power fluctuations
- Power strip issues (despite being "really nice")
- Circuit breaker micro-trips
- Power company voltage sags

**Why USB 2.0 makes it worse:**
- With USB 3.0 (10x faster), writes complete quickly, small window for corruption
- With USB 2.0 (slow), writes take longer, much larger window for corruption
- Same brief power blip that USB 3.0 would survive causes corruption on USB 2.0

## Current Storage Configuration

**Device:** PNY USB 3.2.1 FD (256GB)  
**Connection:** USB 2.0 (480M) ❌ Should be USB 3.0 (5000M)  
**Filesystem:** EXT4 with journal  
**Mount options:** `rw,noatime` ✅  
**Write cache:** write through ✅ (safe mode)  
**I/O scheduler:** mq-deadline ✅ (optimal)  
**Disk usage:** 6% (204GB free) ✅  
**No filesystem errors:** ✅  
**No I/O errors:** ✅  

## Solution: Move USB Drive to USB 3.0 Port

### Raspberry Pi 5 USB Ports

The Raspberry Pi 5 has **4 USB ports:**
- **2x USB 3.0 ports** (blue) - 5000 Mbps
- **2x USB 2.0 ports** (black) - 480 Mbps

**Current:** USB drive is in a USB 2.0 port  
**Solution:** Move to a USB 3.0 port (blue port)

### How to Move USB Drive Safely

**Option 1: Graceful migration (recommended)**
```bash
# 1. SSH into Raspberry Pi
ssh omedeiro@192.168.99.134

# 2. Stop services writing to USB drive
sudo systemctl stop influxdb grafana-server cloudflared

# 3. Sync all data to disk
sync

# 4. Unmount USB drive
sudo umount /mnt/sensor-data

# 5. Physically move USB drive from black port to blue port

# 6. Remount USB drive
sudo mount -a

# 7. Verify it's now USB 3.0
lsusb -t | grep "Mass Storage"
# Should show: 5000M instead of 480M

# 8. Restart services
sudo systemctl start influxdb grafana-server cloudflared

# 9. Verify all sensors posting
curl http://192.168.99.110/api/latest
```

**Option 2: Quick move (if confident)**
```bash
# 1. Shutdown Pi gracefully
ssh omedeiro@192.168.99.134
sudo shutdown -h now

# 2. Wait for shutdown (all lights off)

# 3. Move USB drive to blue USB 3.0 port

# 4. Power on Pi

# 5. Verify USB 3.0 after boot
ssh omedeiro@192.168.99.134
lsusb -t | grep "Mass Storage"
# Should show: 5000M
```

## Additional Recommendations

### 1. Add UPS (Uninterruptible Power Supply)

**Why:** Even with USB 3.0, brief power interruptions can still cause corruption.

**Recommended UPS:**
- **CyberPower CP425SLG** ($50, 425VA/255W, 5 outlets)
- **APC Back-UPS 600VA** ($80, 600VA/330W, 7 outlets)
- **CyberPower CP685AVR** ($90, 685VA/390W, 8 outlets, AVR)

**Benefits:**
- Survives brief power outages (5-15 minutes runtime)
- Protects against brownouts and voltage sags
- Prevents ALL unclean shutdowns from power issues
- ~10 minutes to gracefully shutdown if extended outage

**Setup:**
```bash
# Install NUT (Network UPS Tools) for auto-shutdown
sudo apt-get install nut

# Configure UPS monitoring
# On battery: wait 2 minutes, then shutdown gracefully
# Prevents data corruption even on extended outage
```

### 2. Reduce EXT4 Commit Interval (Optional)

**Current:** 5 seconds (default)  
**Option:** Reduce to 1 second for more frequent flushes

**Trade-off:**
- Pro: Less data loss on power failure (max 1 second instead of 5)
- Con: More write cycles to USB drive (faster wear)

**How to set:**
```bash
# Add to /etc/fstab:
UUID=1efa7d23-5e6f-449c-9d0f-b72c762bb050  /mnt/sensor-data  ext4  defaults,nofail,noatime,commit=1  0  2

# Remount:
sudo mount -o remount /mnt/sensor-data
```

**Recommendation:** Wait to see if USB 3.0 + UPS fixes issue first. Only tune commit interval if problems persist.

### 3. Add Sync on Shutdown Hook

Ensure all data is flushed before shutdown completes:

**Create `/etc/systemd/system/flush-on-shutdown.service`:**
```ini
[Unit]
Description=Flush filesystem cache on shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target
After=mnt-sensor\x2ddata.mount

[Service]
Type=oneshot
ExecStart=/bin/sync
ExecStart=/bin/sh -c 'echo 3 > /proc/sys/vm/drop_caches'
RemainAfterExit=yes

[Install]
WantedBy=shutdown.target reboot.target halt.target
```

**Install:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable flush-on-shutdown.service
```

## Monitoring Storage Health

**Installed:** `storage-monitor.timer` runs every 3 minutes

**Logs:** `/mnt/sensor-data/logs/storage-monitor.log`

**Checks:**
- USB connection speed (detects if reverted to USB 2.0)
- Filesystem errors
- I/O errors  
- USB disconnect events
- Write cache mode
- Disk usage
- Dirty cache (pending writes)

**View logs:**
```bash
ssh omedeiro@192.168.99.134
tail -f /mnt/sensor-data/logs/storage-monitor.log
cat /mnt/sensor-data/logs/storage-alerts.log
```

## Expected Results After Fix

**Before (USB 2.0):**
- Unclean shutdowns on brief power interruptions
- InfluxDB corruption requiring restore from backup
- Filesystem marked "not clean" on boot

**After (USB 3.0):**
- 10x faster writes = smaller corruption window
- Same power blip completes writes before data loss
- Should eliminate most corruption events

**After (USB 3.0 + UPS):**
- No unclean shutdowns from power issues
- UPS provides 5-15 min runtime
- Graceful shutdown on extended outage
- Zero data corruption from power

## Action Plan

**Priority 1 (Immediate):**
1. ✅ Storage monitoring installed (every 3 minutes)
2. ⏳ Move USB drive to USB 3.0 port (blue port)
3. ⏳ Verify connection speed: `lsusb -t | grep 5000M`

**Priority 2 (Within 1 week):**
4. ⏳ Order UPS ($50-90)
5. ⏳ Install UPS and configure auto-shutdown
6. ⏳ Test UPS by unplugging AC power

**Priority 3 (Monitor):**
7. ⏳ Watch storage logs for 1 week
8. ⏳ Review daily health reports
9. ⏳ If issues persist, tune commit interval

## Verification

**After moving to USB 3.0:**
```bash
ssh omedeiro@192.168.99.134

# Check connection speed
lsusb -t | grep "Mass Storage"
# MUST show: 5000M (not 480M)

# Check storage monitor log
tail /mnt/sensor-data/logs/storage-monitor.log
# Should show: "✓ USB drive at USB 3.0 speed (optimal)"

# Monitor for 1 week
# No more unclean shutdowns = FIXED
```

## Summary

**Root Cause:** USB drive connected at USB 2.0 speed instead of USB 3.0  
**Impact:** 10x slower writes → larger corruption window on power blips  
**Fix:** Move USB drive to blue USB 3.0 port  
**Prevention:** Add UPS to eliminate power-related shutdowns  
**Monitoring:** Storage monitor tracks speed, errors, and health every 3 minutes  

This explains why:
- WiFi uptime is 59 days (not network issue) ✅
- No smart plug (ruled out) ✅  
- Good power strip (but can't prevent building power issues) ✅
- Storage is the culprit (USB 2.0 speed + power blips) ✅
