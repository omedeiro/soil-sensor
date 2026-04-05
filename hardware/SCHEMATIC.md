# Electrical Schematic — Wiring Guide
## ESP8266 + Capacitive Soil Moisture Sensor v1.2

```
                          ┌─────────────────────────┐
                          │      ESP8266 Module      │
                          │      (NodeMCU v2 /       │
                          │       Wemos D1 Mini)     │
                          │                          │
 USB 5V ──────────────────┤ VIN              3V3  ├──────┐
                          │                          │     │
                     ┌────┤ GND              D0   ├      │
                     │    │                          │     │
                     │    │ A0 ◄─── Sensor AOUT      │     │
                     │    │                          │     │
                     │    │ D1   (GPIO5)  ─ free     │     │
                     │    │ D2   (GPIO4)  ─ free     │     │
                     │    │ D3   (GPIO0)  ─ free     │     │
                     │    │ D4   (GPIO2)  ─ LED      │     │
                     │    │ D5   (GPIO14) ─ free     │     │
                     │    │ D6   (GPIO12) ─ free     │     │
                     │    │ D7   (GPIO13) ─ free     │     │
                     │    │ D8   (GPIO15) ─ free     │     │
                     │    └─────────────────────────┘     │
                     │                                     │
                     │    ┌─────────────────────────┐     │
                     │    │  Capacitive Soil Moisture│     │
                     │    │  Sensor v1.2             │     │
                     │    │                          │     │
                     │    │  VCC  ──────────────────────────┘
                     │    │                          │
                     └────┤  GND                     │
                          │                          │
          To ESP A0 ◄─────┤  AOUT (Analog Output)   │
                          │                          │
                          └─────────────────────────┘
```

## Connections Table

| Sensor Pin | ESP8266 Pin | Wire Color (suggested) | Notes                        |
|------------|-------------|------------------------|------------------------------|
| **VCC**    | **3V3**     | 🔴 Red                | 3.3 V supply                 |
| **GND**    | **GND**     | ⚫ Black              | Common ground                |
| **AOUT**   | **A0**      | 🟡 Yellow             | Analog moisture signal       |

## Important Notes

### Power Supply
- The capacitive soil moisture sensor v1.2 operates at **3.3 V – 5 V**.
- When powered from the ESP8266 **3V3** pin, the analog output range fits
  within the ESP8266 ADC range (**0 – 1.0 V** input, mapped 0–1023).
- **Do NOT** power the sensor from **5 V (VIN)** unless you add a voltage
  divider on the AOUT line — the ESP8266 ADC is limited to **1.0 V max**.

### Voltage Divider (if powering sensor at 5 V)
If you must use 5 V for better resolution:
```
  Sensor AOUT ──── R1 (100 kΩ) ──┬── ESP8266 A0
                                  │
                             R2 (220 kΩ)
                                  │
                                 GND

  V_A0 = V_AOUT × R2 / (R1 + R2)
       ≈ V_AOUT × 0.687
  Max ≈ 3.3 V × 0.687 ≈ 2.27 V  (still > 1 V, adjust R values as needed)
```
For a safe 5 V setup use **R1 = 220 kΩ, R2 = 100 kΩ**:
```
  V_A0 ≈ V_AOUT × 100 / 320 ≈ 0.31 × V_AOUT
  At 3.3 V output → ~1.03 V  (just at the limit)
```

### Sensor Placement
- Insert the sensor into the soil **up to the marked line** on the PCB.
- Do **not** submerge the electronics section — only the capacitive
  probe area is waterproof.
- For outdoor use, seal the top of the sensor with hot glue or
  conformal coating.

### Calibration Procedure
1. **Air value**: Hold the sensor in open air and note the ADC reading.
2. **Water value**: Submerge the probe section in a glass of water and
   note the ADC reading.
3. Enter these values in `firmware/src/config.h`:
   ```c
   #define SENSOR_AIR_VALUE    780   // your air reading
   #define SENSOR_WATER_VALUE  360   // your water reading
   ```
   Or use the HTTP API at runtime:
   ```bash
   curl -X POST "http://<device-ip>/api/calibrate?air=780&water=360"
   ```
