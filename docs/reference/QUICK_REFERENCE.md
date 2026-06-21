# Quick Reference: Sensor Configuration

## Dashboard Features

When you open the Grafana dashboard, you'll see:

- **🌿 All Sensors** heading when viewing all sensors
- **🌱 [Plant Name]** heading when a specific sensor is selected (e.g., "🌱 Rubber Tree")
- **Default 7-day view** - Shows the last week of data automatically
- **Dropdown filtering** - All panels filter when you select a sensor

---

## Common Tasks

### 1. Change a Plant Name

```bash
# Edit sensors-config.json
vim sensors-config.json

# Change "plant": "Rubber Tree" to "plant": "Fiddle Leaf Fig"

# Regenerate and deploy
./scripts/generate-dashboard.py
./scripts/upload-dashboard-to-pi.sh
```

**Time:** ~30 seconds

---

### 2. Add a New Sensor

```bash
# 1. Add entry to sensors-config.json
# Copy an existing sensor block and modify:
{
  "id": "sensor-8",
  "plant": "Spider Plant",
  "location": "bathroom",
  "ip": "192.168.99.XXX",
  "mac": "XX:XX:XX:XX:XX:XX",
  "color": "#00D9FF",
  "thresholds": {"low": 33, "medium": 67},
  "colorSteps": [
    {"value": null, "color": "#004d5c"},
    {"value": 33, "color": "#0080a8"},
    {"value": 67, "color": "#00D9FF"}
  ]
}

# 2. Generate and upload dashboard
./scripts/generate-dashboard.py
./scripts/upload-dashboard-to-pi.sh

# 3. Configure ESP8266
cd firmware
# Edit src/config.h:
#   DEVICE_ID = "sensor-8"
#   DEVICE_LOCATION = "bathroom"

# 4. Flash firmware
pio run --target upload

# 5. Monitor serial output
pio device monitor
```

**Time:** ~5 minutes (including firmware flash)

---

### 3. Change Sensor Colors

```bash
# Edit sensors-config.json
# Change "color": "#73BF69" to your new color

# Update colorSteps to match (dark → light gradient):
"colorSteps": [
  {"value": null, "color": "#DARK_SHADE"},
  {"value": 33, "color": "#MEDIUM_SHADE"},
  {"value": 67, "color": "#LIGHT_SHADE"}
]

# Regenerate and deploy
./scripts/generate-dashboard.py
./scripts/upload-dashboard-to-pi.sh
```

**Time:** ~1 minute

---

### 4. Adjust Moisture Thresholds

```bash
# Edit sensors-config.json
# For a plant that likes it dry (e.g., cactus):
"thresholds": {
  "low": 10,
  "medium": 30
}

# For a plant that likes it wet (e.g., fern):
"thresholds": {
  "low": 50,
  "medium": 75
}

# Regenerate and deploy
./scripts/generate-dashboard.py
./scripts/upload-dashboard-to-pi.sh
```

**Time:** ~30 seconds

---

### 5. Validate Configuration

```bash
# Before generating dashboard, check for errors:
./scripts/validate-config.py

# Sample output:
# ✓ Configuration is valid (7 sensors)
#
# Sensors:
#   sensor-1   → Rubber Tree          (bed-room)
#   sensor-2   → Monstera             (living-room)
#   ...
```

**Time:** ~5 seconds

---

### 6. Remove a Sensor

```bash
# 1. Remove sensor entry from sensors-config.json
vim sensors-config.json
# Delete the entire {...} block for that sensor

# 2. Regenerate and deploy
./scripts/generate-dashboard.py
./scripts/upload-dashboard-to-pi.sh

# 3. Optionally: power off the ESP8266 or repurpose it
```

**Time:** ~1 minute

---

## File Locations

| File | Purpose |
|------|---------|
| `sensors-config.json` | Master configuration (edit this) |
| `validate-config.py` | Validate config before generating |
| `generate-dashboard.py` | Generate dashboard from config |
| `upload-dashboard-to-pi.sh` | Deploy to Grafana |
| `grafana-dashboards/soil-moisture-main.json` | Generated dashboard (don't edit) |
| `firmware/src/config.h` | ESP8266 configuration (per sensor) |

---

## Current Sensor Colors

Active sensors use these colors for easy visual distinction:

| Sensor | Plant | Color | Hex |
|--------|-------|-------|-----|
| 1 | Rubber Tree | Green | `#73BF69` |
| 2 | Monstera | Yellow | `#F2CC0C` |
| 3 | Avocado | Blue | `#5794F2` |
| 4 | Basil - auk | Red | `#FF6B6B` |
| 5 | ZZ Plant | Purple | `#B877D9` |
| 6 | Ficus Elastica Ruby | Orange | `#FF9830` |
| 7 | Basil - pot | Cyan | `#5DDBDB` |

**Tip:** Use distinct colors for easy identification in graphs. [Coolors.co](https://coolors.co/) is a great tool for generating color palettes.

---

## Color Palette Ideas

Need inspiration? Here are some nice color schemes:

### Earth Tones
- `#8B4513` (Saddle Brown)
- `#CD853F` (Peru)
- `#D2691E` (Chocolate)
- `#A0522D` (Sienna)

### Pastels
- `#FFB3BA` (Light Pink)
- `#FFDFBA` (Light Orange)
- `#FFFFBA` (Light Yellow)
- `#BAFFC9` (Light Green)
- `#BAE1FF` (Light Blue)

### Vibrant
- `#FF6B6B` (Bright Red)
- `#4ECDC4` (Turquoise)
- `#45B7D1` (Sky Blue)
- `#FFA07A` (Light Salmon)
- `#98D8C8` (Mint)

Generate custom palettes: [Coolors.co](https://coolors.co/)

---

## Advanced Configuration

### Grafana Configuration

The `grafana` section in `sensors-config.json` contains InfluxDB connection settings:

```json
"grafana": {
  "influxdb_datasource_uid": "cflk0i2e2nwu8d",  // Grafana datasource UID
  "bucket": "sensor-readings",                   // InfluxDB bucket name
  "measurement": "sensor_reading"                // InfluxDB measurement name
}
```

**Note:** These rarely need to change unless you're setting up a new InfluxDB instance or datasource.

---

## Troubleshooting

### "Configuration validation failed"

**Problem:** `./scripts/generate-dashboard.py` fails validation

**Solution:** Run `./scripts/validate-config.py` to see specific errors. Common issues:
- Missing comma after a sensor block
- Invalid color format (must be `#RRGGBB`)
- Duplicate sensor IDs
- Missing required fields

### "Dashboard not updating in Grafana"

**Problem:** Changes don't appear after upload

**Solution:**
1. Check upload output for errors
2. Hard refresh browser: `Ctrl+Shift+R` (Windows/Linux) or `Cmd+Shift+R` (Mac)
3. Verify file was modified: `ls -lh grafana-dashboards/soil-moisture-main.json`
4. Check Grafana logs on Pi: `ssh omedeiro@192.168.99.134 "sudo journalctl -u grafana-server -f"`

### "Sensor not appearing in dropdown"

**Problem:** Added sensor to config but not in Grafana dropdown

**Causes:**
1. Sensor hasn't sent data yet (InfluxDB query requires recent data)
2. ESP8266 `DEVICE_ID` doesn't match `sensors-config.json`
3. Dashboard filter excludes the location

**Solution:**
1. Check ESP8266 serial: `pio device monitor` → look for `[DB] ✓ Posted to InfluxDB`
2. Verify `config.h` matches JSON: `DEVICE_ID "sensor-X"`
3. Check InfluxDB for data:
   ```bash
   ssh omedeiro@192.168.99.134
   influx query "SELECT last(moisture) FROM sensor_reading GROUP BY device_id"
   ```

---

## Best Practices

✅ **DO:**
- Validate config before generating: `./scripts/validate-config.py`
- Use descriptive plant names: "Monstera Deliciosa" not "Plant 2"
- Choose distinct colors for easy visual identification
- Keep thresholds between 0-100
- Commit `sensors-config.json` to Git after changes

❌ **DON'T:**
- Edit `grafana-dashboards/soil-moisture-main.json` manually (auto-generated)
- Use duplicate sensor IDs
- Use invalid hex colors (e.g., `#GGG`)
- Set `threshold.low >= threshold.medium`
- Delete sensors that are still online (causes orphaned data)

---

## See Also

- **[README.md](README.md)** - Project overview and architecture
- **[AGENTS.md](AGENTS.md)** - Technical reference for AI agents
- **[grafana-dashboards/README.md](grafana-dashboards/README.md)** - Dashboard guide
- **[firmware/README.md](firmware/README.md)** - ESP8266 firmware guide
