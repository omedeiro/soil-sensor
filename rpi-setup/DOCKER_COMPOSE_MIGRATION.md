# Docker Compose Migration Guide

## Overview
This guide explains how to migrate from standalone Docker containers to Docker Compose for better networking, automatic restarts, and easier management.

## Current Setup (Before Migration)
- InfluxDB: Running as standalone container at `172.17.0.2:8086`
- Grafana: Running as standalone container at `172.17.0.3:3000`
- Datasources: Hardcoded to use `http://172.17.0.2:8086`

## New Setup (After Migration)
- Both services managed by Docker Compose
- Custom bridge network with predictable IPs
- Grafana datasource uses container name: `http://influxdb:8086`
- Automatic restart on boot
- Health checks for both services

## Benefits
1. **No more hardcoded IPs** - Use container names (DNS resolution)
2. **Automatic startup** - Grafana waits for InfluxDB to be healthy
3. **Easier management** - Single `docker-compose` command
4. **Better logging** - Unified logging via `docker-compose logs`
5. **Health monitoring** - Built-in healthchecks

---

## Migration Steps

### 1. Backup Current State

```bash
# Create backup directory
mkdir -p /mnt/sensor-data/migration-backup-$(date +%Y%m%d)

# Stop existing containers
docker stop grafana influxdb

# Backup container configs (optional)
docker inspect influxdb > /mnt/sensor-data/migration-backup-$(date +%Y%m%d)/influxdb-config.json
docker inspect grafana > /mnt/sensor-data/migration-backup-$(date +%Y%m%d)/grafana-config.json

# Data is already on disk at /mnt/sensor-data/{influxdb,grafana}
# No need to backup volumes - they're already persistent
```

### 2. Remove Old Containers

**IMPORTANT:** This does NOT delete your data (data is in `/mnt/sensor-data`)

```bash
# Remove containers (keeps data intact)
docker rm influxdb grafana

# Verify data is still there
ls -la /mnt/sensor-data/influxdb
ls -la /mnt/sensor-data/grafana
```

### 3. Deploy with Docker Compose

```bash
cd ~/rpi-setup

# Start services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

### 4. Update Grafana Datasources

The datasource URL needs to change from `http://172.17.0.2:8086` to `http://influxdb:8086`.

**Option A: Automated Update (recommended)**
```bash
./update-grafana-datasources.sh
```

**Option B: Manual Update via Grafana UI**
1. Open Grafana: `http://192.168.99.134:3000`
2. Navigate to: Configuration → Data Sources
3. For each InfluxDB datasource:
   - Change URL from `http://172.17.0.2:8086` to `http://influxdb:8086`
   - Click "Save & Test"

### 5. Verify Functionality

```bash
# Check container health
docker-compose ps

# Test InfluxDB connectivity
curl -I http://localhost:8086/health

# Test Grafana connectivity
curl -I http://localhost:3000/api/health

# Verify sensor data is still flowing
curl -s -XPOST "http://localhost:8086/api/v2/query?org=soil-monitoring" \
  -H "Authorization: Token YOUR_TOKEN" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket: "sensor-readings") |> range(start: -5m) |> limit(n: 1)'
```

### 6. Test Grafana Dashboards

1. Open Grafana at `https://grafana.owenmedeiros.com`
2. Navigate to main soil moisture dashboard
3. Verify panels are loading data
4. Check uptime panel (should show Raspberry Pi uptime)

---

## Rollback Plan (If Something Goes Wrong)

If the migration fails, you can quickly rollback:

```bash
# Stop Docker Compose services
docker-compose down

# Start original containers manually
docker run -d \
  --name influxdb \
  -p 8086:8086 \
  -v /mnt/sensor-data/influxdb:/var/lib/influxdb2 \
  --restart unless-stopped \
  influxdb:2.7

docker run -d \
  --name grafana \
  -p 3000:3000 \
  -v /mnt/sensor-data/grafana:/var/lib/grafana \
  -e GF_SECURITY_ALLOW_EMBEDDING=true \
  -e GF_AUTH_ANONYMOUS_ENABLED=true \
  -e GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer \
  --restart unless-stopped \
  grafana/grafana:latest

# Revert datasources to use 172.17.0.2
# (Use Grafana UI or restore datasource config from backup)
```

---

## Docker Compose Commands Reference

```bash
# Start services (detached mode)
docker-compose up -d

# Stop services
docker-compose stop

# Restart services
docker-compose restart

# View logs (all services)
docker-compose logs -f

# View logs (specific service)
docker-compose logs -f influxdb
docker-compose logs -f grafana

# Check service status
docker-compose ps

# Stop and remove containers (keeps data)
docker-compose down

# Stop and remove everything including networks
docker-compose down --volumes  # ⚠️  WARNING: This deletes data!

# Rebuild containers after config change
docker-compose up -d --build
```

---

## Automatic Startup on Boot

Docker Compose services with `restart: unless-stopped` will automatically start on boot.

To ensure Docker itself starts on boot:

```bash
sudo systemctl enable docker
```

To check if services auto-started after reboot:

```bash
# Reboot Pi
sudo reboot

# After reboot, check status
docker-compose ps
```

---

## Troubleshooting

### Services Not Starting

```bash
# Check logs
docker-compose logs

# Check individual service
docker-compose logs influxdb
docker-compose logs grafana

# Restart specific service
docker-compose restart grafana
```

### Grafana Can't Connect to InfluxDB

```bash
# Verify network connectivity
docker-compose exec grafana ping -c 3 influxdb

# Check InfluxDB health
docker-compose exec grafana curl -I http://influxdb:8086/health

# Verify datasource URL in Grafana
# Should be: http://influxdb:8086 (NOT 172.17.0.2)
```

### ESP8266 Sensors Can't Reach InfluxDB

**This should NOT happen** - ESP8266 sensors connect to `192.168.99.134:8086` (host port), not container network.

If sensors can't post data:

```bash
# Verify port 8086 is exposed
docker-compose ps
# Should show: 0.0.0.0:8086->8086/tcp

# Test from another machine
curl -I http://192.168.99.134:8086/health
```

### Containers Keep Restarting

```bash
# Check why container is failing
docker-compose logs --tail=50 influxdb

# Common causes:
# - Permission issues on /mnt/sensor-data
# - Disk full
# - Corrupted database files
```

---

## Post-Migration Checklist

- [ ] Both containers running: `docker-compose ps`
- [ ] Healthchecks passing: `docker ps` (should show "healthy")
- [ ] InfluxDB accessible: `curl http://localhost:8086/health`
- [ ] Grafana accessible: `curl http://localhost:3000/api/health`
- [ ] Datasources updated: `http://influxdb:8086` (not 172.17.0.2)
- [ ] Dashboards loading data correctly
- [ ] Uptime panel showing Raspberry Pi metrics
- [ ] ESP8266 sensors still posting data
- [ ] Cloudflare Tunnel still working: `https://grafana.owenmedeiros.com`
- [ ] System metrics collector still running every 60s

---

## Advanced: Dashboard Provisioning

To auto-import dashboards on Grafana startup:

1. Create provisioning directory:
   ```bash
   mkdir -p ~/rpi-setup/grafana-provisioning/{datasources,dashboards}
   ```

2. Create datasource config:
   ```yaml
   # grafana-provisioning/datasources/influxdb.yaml
   apiVersion: 1
   datasources:
     - name: InfluxDB
       type: influxdb
       access: proxy
       url: http://influxdb:8086
       jsonData:
         version: Flux
         organization: soil-monitoring
         defaultBucket: sensor-readings
         tlsSkipVerify: true
       secureJsonData:
         token: YOUR_READ_TOKEN
   ```

3. Create dashboard config:
   ```yaml
   # grafana-provisioning/dashboards/soil-sensors.yaml
   apiVersion: 1
   providers:
     - name: 'Soil Sensors'
       orgId: 1
       folder: ''
       type: file
       options:
         path: /etc/grafana/provisioning/dashboards
   ```

4. Copy dashboards:
   ```bash
   cp ~/soil-sensor/grafana-dashboards/*.json \
      ~/rpi-setup/grafana-provisioning/dashboards/
   ```

5. Uncomment provisioning volume in `docker-compose.yml`:
   ```yaml
   volumes:
     - ./grafana-provisioning:/etc/grafana/provisioning
   ```

6. Restart Grafana:
   ```bash
   docker-compose restart grafana
   ```

---

## Summary

**Before:** Standalone containers with hardcoded IPs  
**After:** Docker Compose with container name DNS resolution

**Key Change:** Grafana datasource URL  
- Old: `http://172.17.0.2:8086`  
- New: `http://influxdb:8086`

**Migration Time:** ~5 minutes  
**Downtime:** ~2 minutes (during container restart)  
**Risk:** Low (data persists on disk, easy rollback)
