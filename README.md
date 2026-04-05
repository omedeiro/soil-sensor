# 🌱 Soil Moisture Monitoring System

An active soil moisture monitoring system built with an **ESP8266** microcontroller
and a **capacitive soil moisture sensor (v1.2)**. The device connects to WiFi,
logs moisture readings over time, and serves a live dashboard accessible from
any browser on your local network.

---

## Features

- **Capacitive sensing** — corrosion-resistant, no exposed metal electrodes
- **WiFi provisioning** — captive-portal setup via WiFiManager (no hard-coded credentials needed)
- **NTP time sync** — every reading is timestamped
- **In-memory ring-buffer** — stores up to 24 hours of data (at 1-min intervals)
- **Live web dashboard** — beautiful dark-mode UI, auto-refreshes every 5 seconds
- **JSON REST API** — `/api/latest`, `/api/history`, `/api/calibrate`, `/api/reset`
- **Runtime calibration** — adjust air/water ADC values via HTTP without reflashing
- **Auto-reconnect** — recovers from WiFi drops automatically

## Project Structure

```
soil-sensor/
├── firmware/                  # ESP8266 Arduino firmware (PlatformIO)
│   ├── platformio.ini         # Build configuration
│   └── src/
│       ├── main.cpp           # Entry point — setup & loop
│       ├── config.h           # All configurable constants
│       ├── sensor.h/.cpp      # ADC driver & moisture calculation
│       ├── wifi_manager.h/.cpp# WiFi connection + captive portal
│       ├── data_logger.h/.cpp # Ring-buffer data storage
│       └── web_server.h/.cpp  # HTTP server + dashboard
├── hardware/                  # Electrical documentation
│   ├── SCHEMATIC.md           # Wiring diagram & notes
│   ├── schematic.json         # Machine-readable connection map
│   └── BOM.md                 # Bill of materials
├── LICENSE
└── README.md
```

## Hardware Setup

### Components Needed

| Component                             | Qty |
|---------------------------------------|-----|
| ESP8266 dev board (NodeMCU / D1 Mini) | 1   |
| Capacitive Soil Moisture Sensor v1.2  | 1   |
| Jumper wires (female-to-female)       | 3   |
| Micro-USB cable                       | 1   |

### Wiring

```
Sensor VCC  ────► ESP8266 3V3
Sensor GND  ────► ESP8266 GND
Sensor AOUT ────► ESP8266 A0
```

> ⚠️ Power the sensor from **3V3**, not 5 V. The ESP8266 ADC accepts
> a maximum of 1.0 V. See `hardware/SCHEMATIC.md` for a voltage-divider
> option if you need to use 5 V.

Full wiring diagrams and notes → [`hardware/SCHEMATIC.md`](hardware/SCHEMATIC.md)

## Firmware Setup

### Prerequisites

- [PlatformIO](https://platformio.org/) (CLI or VS Code extension)
- USB driver for your ESP8266 board (CP2102 or CH340)

### Build & Flash

```bash
cd firmware

# Build
pio run

# Upload to board
pio run --target upload

# Open serial monitor
pio device monitor
```

### Configuration

Edit `firmware/src/config.h` to customize:

| Setting              | Default       | Description                         |
|----------------------|---------------|-------------------------------------|
| `SENSOR_AIR_VALUE`   | `780`         | ADC reading in open air (dry)       |
| `SENSOR_WATER_VALUE` | `360`         | ADC reading submerged in water      |
| `READ_INTERVAL_MS`   | `60000` (1 m) | How often to sample the sensor      |
| `LOG_BUFFER_SIZE`    | `1440`        | Max readings in memory (~24 h)      |
| `UTC_OFFSET_SEC`     | `0`           | Timezone offset from UTC in seconds |
| `AP_NAME`            | `SoilSensor-Setup` | Captive-portal AP name         |

### WiFi Setup

1. Power on the device.
2. If no WiFi credentials are saved, the ESP8266 creates an access point
   named **SoilSensor-Setup**.
3. Connect to that AP with your phone or laptop.
4. A captive portal opens — select your WiFi network and enter the password.
5. The device reboots and connects to your network.

### Calibration

1. Hold the sensor in **open air** → note the serial output `raw=XXX` → that's your **air value**.
2. Insert the probe into a **glass of water** → note `raw=XXX` → that's your **water value**.
3. Update `config.h` and reflash, **or** use the HTTP API:
   ```bash
   curl -X POST "http://<device-ip>/api/calibrate?air=780&water=360"
   ```

## API Reference

| Method | Endpoint           | Description                     |
|--------|--------------------|---------------------------------|
| GET    | `/`                | Live dashboard (HTML)           |
| GET    | `/api/latest`      | Latest reading (JSON)           |
| GET    | `/api/history`     | All stored readings (JSON)      |
| POST   | `/api/calibrate`   | Set `air` / `water` values      |
| POST   | `/api/reset`       | Clear all logged data           |

### Example Response — `/api/latest`

```json
{
  "ts": 1775000000,
  "raw": 520,
  "moisture": 61.9
}
```

## License

See [LICENSE](LICENSE) for details.