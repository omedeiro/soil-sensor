# Grafana Dashboard Snapshots - v2.3.0

Live interactive snapshots of all 6 dashboards (never expire).

## Created Snapshots

### 1. 🌱 Soil Moisture Dashboard (Main)
**Snapshot URL:** http://192.168.99.134:3000/dashboard/snapshot/rNDWAtHiztcOZPsRSsmq01KOOMKprBke

**Features shown:**
- Raspberry Pi uptime panel (top status bar)
- 4 moisture gauges with color gradients
- Moisture trends chart
- Recent readings table
- Watering recommendations

**Snapshot created:** 2026-05-18  
**Expires:** Never

---

### 2. 🖥️ Raspberry Pi Health
**Snapshot URL:** http://192.168.99.134:3000/dashboard/snapshot/rKIaQQd6EGDlun3H76qPamegenl9FFQK

**Features shown:**
- System uptime
- CPU usage and temperature
- RAM and disk usage
- Historical metrics

**Snapshot created:** 2026-05-18  
**Expires:** Never

---

## Creating Additional Snapshots Manually

For the remaining dashboards, create snapshots manually:

### Steps:

1. **Open dashboard** in Grafana:
   - Sensor Details: http://192.168.99.134:3000/d/sensor-details-v1
   - System Health: http://192.168.99.134:3000/d/system-health-v1
   - Alerts Overview: http://192.168.99.134:3000/d/alerts-overview-v1
   - Mobile Summary: http://192.168.99.134:3000/d/mobile-summary-v1

2. **Click Share icon** (top right corner)

3. **Go to Snapshot tab**

4. **Configure snapshot:**
   - **Snapshot name:** `[Dashboard Name] v2.3.0`
   - **Expire:** Never
   - **Timeout:** 30 seconds (default)

5. **Click "Local Snapshot"** (keeps snapshot on your Pi, not public server)

6. **Copy the URL** and add it to this file

---

## Snapshot Management

### View All Snapshots
```bash
curl -u admin:admin http://192.168.99.134:3000/api/dashboard/snapshots
```

### Delete a Snapshot
Use the delete URL provided when snapshot was created, or:
```bash
curl -u admin:admin -X DELETE \
  http://192.168.99.134:3000/api/snapshots-delete/[DELETE_KEY]
```

**Delete Keys:**
- Soil Moisture Dashboard: `o5huNsYc2PLB0n0goTUs6gd2CpD0t8z0`
- Raspberry Pi Health: `cxJLcyxZ3ZXCXkZgnpe915simvmmaEPZ`

---

## Using Snapshots in Documentation

### In README.md:

```markdown
## Dashboard Preview

### Live Interactive Dashboards (Snapshots)

View live snapshots of the dashboards (no login required):

- [🌱 Soil Moisture Dashboard](http://192.168.99.134:3000/dashboard/snapshot/rNDWAtHiztcOZPsRSsmq01KOOMKprBke) - Main overview with all sensors
- [🖥️ Raspberry Pi Health](http://192.168.99.134:3000/dashboard/snapshot/rKIaQQd6EGDlun3H76qPamegenl9FFQK) - System metrics and uptime
- [Add other snapshots here]

**Note:** Snapshots show data from the moment of creation. For live data, access Grafana directly at http://192.168.99.134:3000
```

---

## Updating Snapshots

When dashboards change or you want fresh data:

1. Delete old snapshots using delete URLs above
2. Create new snapshots following the manual steps
3. Update this file with new snapshot URLs
4. Update README.md with new links

---

## Notes

- **Local snapshots** are stored on your Raspberry Pi at `/var/lib/grafana/data/snapshots/`
- **Never expire** means snapshots stay available until manually deleted
- **No authentication required** - Anyone with the link can view
- **Static data** - Snapshots don't update, they show data from creation time
- **Interactive** - You can still zoom, hover, change time ranges on snapshot data

---

Last updated: 2026-05-18
