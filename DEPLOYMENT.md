# 🌱 Deployment Guide — Soil Moisture Monitor

## 📱 Access from Your Phone

Your device is already deployed and accessible! Here's how to monitor it:

### Quick Access

**Device IP:** `192.168.99.70`

1. **From any device on your WiFi network:**
   - Open your phone browser (Safari, Chrome, etc.)
   - Go to: **`http://192.168.99.70`**
   - Bookmark it for easy access!

2. **The dashboard shows:**
   - 🌡️ Current moisture percentage (updates every 5 seconds)
   - 📊 Raw ADC sensor value
   - ⏰ Last reading timestamp
   - 📈 Total readings logged
   - 🌐 Device IP address

### API Endpoints (for advanced use)

```bash
# Latest reading (JSON)
http://192.168.99.70/api/latest

# All historical data
http://192.168.99.70/api/history

# Calibrate sensor
curl -X POST "http://192.168.99.70/api/calibrate?air=780&water=360"

# Clear logged data
curl -X POST "http://192.168.99.70/api/reset"
```

---

## 🪴 Physical Deployment for Your Plant

### Setup Steps:

1. **Power the device:**
   - Use a USB wall adapter (5V, any phone charger works)
   - Or use a USB power bank for portable/outdoor deployment

2. **Insert the sensor into soil:**
   - Push the probe **up to the marked line** on the PCB
   - **DO NOT** submerge the electronics section
   - Position near the plant's root zone (2-3 inches deep)

3. **Placement tips:**
   - Keep the ESP8266 board above ground (protect from water)
   - Route the sensor wires neatly
   - Optional: use a waterproof case for the ESP8266 if outdoors

4. **Calibration for your specific soil:**
   ```bash
   # Air value: Remove sensor from soil, let it dry completely
   # Note the "raw" value from dashboard → this is your AIR_VALUE
   
   # Water value: Water the soil heavily until saturated
   # Note the "raw" value → this is your WATER_VALUE
   
   # Update via API:
   curl -X POST "http://192.168.99.70/api/calibrate?air=XXX&water=YYY"
   ```

---

## 📊 Monitoring Schedule

The device automatically:
- ✅ Takes a reading every **60 seconds** (configurable in `config.h`)
- ✅ Stores up to **1440 readings** (~24 hours of data)
- ✅ Syncs time via NTP for accurate timestamps
- ✅ Auto-reconnects if WiFi drops

### Understanding Moisture Levels

| Moisture % | Soil Condition | Action |
|------------|---------------|--------|
| 0-20%      | 🏜️ Very Dry   | Water immediately! |
| 20-40%     | 🌵 Dry        | Consider watering |
| 40-60%     | ✅ Good       | Ideal for most plants |
| 60-80%     | 💧 Moist      | Good for water-loving plants |
| 80-100%    | 💦 Saturated  | May be overwatered |

*(Adjust thresholds based on your specific plant species)*

---

## 🔋 Power Options

### Option 1: USB Wall Adapter (Recommended for indoor)
- Any 5V phone charger works
- Always-on monitoring
- Most reliable

### Option 2: USB Power Bank (For portability)
- 10,000 mAh bank = ~7-10 days runtime
- Good for outdoor/remote plants
- Recharge weekly

### Option 3: Solar (Advanced)
- Solar panel (5V, 1W+) + rechargeable battery
- Truly autonomous outdoor deployment
- Requires additional circuitry

---

## 📱 Bookmark Setup for Easy Access

### iPhone/Safari:
1. Open `http://192.168.99.70` in Safari
2. Tap the **Share** button
3. Select **"Add to Home Screen"**
4. Name it "🌱 Plant Monitor"
5. Now you have a one-tap app icon!

### Android/Chrome:
1. Open `http://192.168.99.70` in Chrome
2. Tap the **⋮** menu
3. Select **"Add to Home screen"**
4. Name it "🌱 Plant Monitor"

---

## 🛠️ Optional: Make IP Address Static

To prevent the IP from changing:

### Method 1: Router DHCP Reservation
1. Log into your router admin panel
2. Find DHCP settings
3. Reserve `192.168.99.70` for MAC: `40:91:51:4f:d9:97`

### Method 2: Hardcode IP (Advanced)
Edit `firmware/src/wifi_manager.cpp` and add static IP configuration.

---

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| Can't access from phone | Make sure phone is on same WiFi network |
| IP changed | Check router DHCP table, or set static IP |
| Sensor reads 0% or 100% always | Check wiring, recalibrate |
| No WiFi connection | Device will create "SoilSensor-Setup" AP |
| Dashboard not updating | Refresh browser, check device power |

---

## 📈 Next Steps / Enhancements

**Easy:**
- [ ] Add multiple sensors (use different GPIO pins + create sensor array)
- [ ] Set up email/SMS alerts for low moisture
- [ ] Create a data export feature (CSV download)

**Medium:**
- [ ] Add MQTT for smart home integration (Home Assistant, etc.)
- [ ] Create graphs showing moisture trends over time
- [ ] Add battery voltage monitoring

**Advanced:**
- [ ] Deep sleep mode for battery efficiency
- [ ] Cloud logging (ThingSpeak, Firebase, InfluxDB)
- [ ] Machine learning for predictive watering

---

## ✅ Your System is Ready!

You can now:
- ✅ Access the dashboard from any phone/computer on your WiFi
- ✅ Monitor soil moisture in real-time
- ✅ Get historical data (last 24 hours)
- ✅ Deploy to your plant with any USB power source

**Enjoy your automated plant monitoring! 🌱**
