/*
 * dht_sensor.cpp
 * DHT22 / AM2302 ambient temperature + humidity sensor driver implementation.
 */

#include "dht_sensor.h"
#include <time.h>
#include <math.h>

DHTSensor::DHTSensor(uint8_t pin, uint8_t type)
    : _dht(pin, type), _pin(pin) {}

void DHTSensor::begin() {
    _dht.begin();
    Serial.printf("[DHT] Initialized DHT22 on pin %d (GPIO)\n", _pin);
    // First read after power-up is often stale/NaN; give the sensor a moment.
    delay(2000);
}

ClimateReading DHTSensor::read() {
    ClimateReading r;
    r.timestamp    = time(nullptr);  // epoch from NTP
    r.temperatureC = 0.0f;
    r.temperatureF = 0.0f;
    r.humidity     = 0.0f;
    r.valid        = false;

    // DHT22 reads can fail intermittently — retry a few times.
    for (int attempt = 0; attempt < 3; attempt++) {
        float h = _dht.readHumidity();
        float c = _dht.readTemperature();  // Celsius

        if (!isnan(h) && !isnan(c)) {
            r.humidity     = h;
            r.temperatureC = c;
            r.temperatureF = c * 1.8f + 32.0f;
            r.valid        = true;
            break;
        }

        Serial.printf("[DHT] Read attempt %d returned NaN, retrying...\n", attempt + 1);
        delay(2000);  // DHT22 needs >2s between reads
        yield();
    }

    if (!r.valid) {
        Serial.println(F("[DHT] ✗ Failed to read sensor (check wiring/pull-up)"));
    }

    return r;
}
