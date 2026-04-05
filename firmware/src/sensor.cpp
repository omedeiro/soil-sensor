/*
 * sensor.cpp
 * Capacitive soil moisture sensor driver implementation
 */

#include "sensor.h"

SoilSensor::SoilSensor(uint8_t pin, int airValue, int waterValue)
    : _pin(pin), _airValue(airValue), _waterValue(waterValue) {}

void SoilSensor::begin() {
    pinMode(_pin, INPUT);
    Serial.println(F("[Sensor] Initialized on pin A0"));
    Serial.printf("[Sensor] Calibration → air=%d  water=%d\n", _airValue, _waterValue);
}

SensorReading SoilSensor::read() {
    SensorReading r;
    r.timestamp   = time(nullptr);  // epoch from NTP
    r.rawValue    = _readRaw();
    r.moisturePct = _rawToPercent(r.rawValue);
    return r;
}

/*  Take multiple ADC samples and return the average to reduce noise. */
int SoilSensor::_readRaw() {
    long sum = 0;
    for (int i = 0; i < SENSOR_READ_COUNT; i++) {
        sum += analogRead(_pin);
        delay(SENSOR_READ_DELAY);
    }
    return (int)(sum / SENSOR_READ_COUNT);
}

/*  Map the raw ADC value to a 0-100 % moisture scale.
 *  A higher ADC value means drier soil (capacitive sensor). */
float SoilSensor::_rawToPercent(int raw) {
    float pct = (float)(_airValue - raw) / (float)(_airValue - _waterValue) * 100.0f;
    if (pct < 0.0f)   pct = 0.0f;
    if (pct > 100.0f)  pct = 100.0f;
    return pct;
}
