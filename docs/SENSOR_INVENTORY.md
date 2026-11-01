# Sensor Inventory

Operational state of the ESP8266 fleet — DHCP leases, MACs, signal strength,
online status. This drifts; it is a snapshot, not a contract. For sensor
names, rooms, colors and thresholds, `sensors-config.json` at the repo root
is the source of truth (and `scripts/validate-config.py` checks it in CI).
Moved here verbatim from `AGENTS.md`.

**ESP8266 Sensors (all on firmware v2.4.0, DHCP, OTA-updatable):**
- **sensor-1** (bed-room, Rubber Tree): `192.168.99.110` (MAC: 68:c6:3a:f6:b3:ae) - online
- **sensor-2** (living-room, Monstera): `192.168.99.149` (MAC: 48:3f:da:19:c0:86) - online
- **sensor-3** (living-room, Avocado): `192.168.99.70` (MAC: 40:91:51:4f:d9:97) - online
- **sensor-4** (guest-room, Micro Greens): `192.168.99.105` (MAC: 48:3f:da:aa:fe:d7) - online
- **sensor-5** (bed-room, ZZ Plant): `192.168.99.89` (MAC: 34:ab:95:16:51:d9) (ESP-1651D9, Wi-Fi 2.4GHz n) - online (weakest signal, RSSI ≈ -71 dBm)
- **sensor-6** (living-room, Ficus Elastica Ruby): `192.168.99.38` (MAC: 48:3f:da:62:f9:07) (Wi-Fi 2.4GHz n) - online
- **sensor-7** (guest-room, Parsley): `192.168.99.141` (MAC: 84:cc:a8:a7:96:32) (Wi-Fi 2.4GHz n) - online
- **sensor-8** (living-room, Ambient Climate — **DHT22/AM2302**, not soil): `192.168.99.182` (MAC: 48:55:19:e6:6c:af) - online
- **sensor-9** (guest-room, Ambient Climate — **DHT22/AM2302**, not soil): `192.168.99.48` (MAC: 7c:87:ce:80:4d:36) - online (not in sensors-config.json; climate sensors are excluded from the soil dashboard config)
- All sensors use **DHCP** (static IP disabled in v2.4.0 — it caused a "thinks it's connected forever" failure after power cycles). IPs above are current DHCP leases; use MAC/ARP to relocate a sensor if its IP changes. Sensors can be unplugged and moved to any outlet; they rejoin automatically.
- **OTA updates:** `pio run -e esp8266-ota --target upload --upload-port <sensor-ip>` (password: `OTA_PASSWORD` in `firmware/src/secrets.h`). USB only needed for bricked/offline boards.
- Web Dashboard: `http://<sensor-ip>` (e.g., `http://192.168.99.110`)
- Reading Interval: 5 minutes (300000ms)
