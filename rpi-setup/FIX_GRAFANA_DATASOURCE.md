# Grafana Datasource Fix - "Connection Refused" Issue

## Problem
After Docker-based rebuild, Grafana dashboards showed "connection refused" error when trying to query InfluxDB.

## Root Cause
Grafana datasources were configured to use `http://localhost:8086`, but when both Grafana and InfluxDB run in Docker containers, they need to communicate via Docker network IPs, not localhost.

## Solution
Update all Grafana datasources to use the InfluxDB container IP address instead of localhost.

### Step 1: Find Container IP
```bash
ps aux | grep docker-proxy | grep 8086
# Output shows: -container-ip 172.17.0.2 -container-port 8086
```

### Step 2: Update Datasources
```bash
# Update main datasource (uid: cflk0i2e2nwu8d)
curl -X PUT http://localhost:3000/api/datasources/uid/cflk0i2e2nwu8d \
  -u admin:admin \
  -H "Content-Type: application/json" \
  -d '{
    "id": 1,
    "uid": "cflk0i2e2nwu8d",
    "name": "influxdb",
    "type": "influxdb",
    "url": "http://172.17.0.2:8086",
    "access": "proxy",
    "basicAuth": false,
    "jsonData": {
      "version": "Flux",
      "organization": "soil-monitoring",
      "defaultBucket": "sensor-readings",
      "httpMode": "POST",
      "timeInterval": "10s",
      "maxSeries": 1000
    },
    "secureJsonData": {
      "token": "YOUR_INFLUX_TOKEN"
    }
  }'

# Update secondary datasource (uid: eforkzscbrldsa)
curl -X PUT http://localhost:3000/api/datasources/uid/eforkzscbrldsa \
  -u admin:admin \
  -H "Content-Type: application/json" \
  -d '{
    "id": 3,
    "uid": "eforkzscbrldsa",
    "name": "InfluxDB",
    "type": "influxdb",
    "url": "http://172.17.0.2:8086",
    "access": "proxy",
    "basicAuth": false,
    "jsonData": {
      "version": "Flux",
      "organization": "soil-monitoring",
      "defaultBucket": "sensor-readings",
      "tlsSkipVerify": true
    },
    "secureJsonData": {
      "token": "YOUR_INFLUX_TOKEN"
    }
  }'
```

### Step 3: Verify
```bash
# Test query from Grafana
curl -X POST http://localhost:3000/api/ds/query \
  -u admin:admin \
  -H "Content-Type: application/json" \
  -d '{
    "queries": [{
      "refId": "A",
      "datasource": {"uid": "cflk0i2e2nwu8d"},
      "query": "from(bucket: \"sensor-readings\") |> range(start: -1h) |> filter(fn: (r) => r._measurement == \"sensor_reading\")",
      "rawQuery": true
    }]
  }'
```

## Prevention
When setting up Docker containers in the future, use Docker Compose with a named network or use container names instead of IPs.

Example docker-compose.yml:
```yaml
version: '3.8'
services:
  influxdb:
    container_name: influxdb
    image: influxdb:2.7
    ports:
      - "8086:8086"
    volumes:
      - /mnt/sensor-data/influxdb:/var/lib/influxdb2
    networks:
      - soil-sensor

  grafana:
    container_name: grafana
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - /mnt/sensor-data/grafana:/var/lib/grafana
    networks:
      - soil-sensor
    environment:
      - GF_SECURITY_ALLOW_EMBEDDING=true
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer

networks:
  soil-sensor:
    driver: bridge
```

Then in Grafana, use `http://influxdb:8086` as the datasource URL.

## Applied On
- Date: 2026-06-11
- InfluxDB container IP: 172.17.0.2
- Grafana container IP: 172.17.0.3
- InfluxDB token: r7LONiwdc3ABOcEYSS5nCL6c6sdUZEPy81Q1D7w7nAyXZDAteUD1C6BYZJe21qX4eOwhRvG2ARYwRkaHwQf17w==
