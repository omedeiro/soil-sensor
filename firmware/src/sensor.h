/*
 * sensor.h
 * Capacitive soil moisture sensor driver
 */

#ifndef SENSOR_H
#define SENSOR_H

#include <Arduino.h>
#include "config.h"

struct SensorReading {
    unsigned long timestamp;   // epoch seconds (from NTP)
    int           rawValue;    // 0-1023
    float         moisturePct; // 0-100 %
};

class SoilSensor {
public:
    SoilSensor(uint8_t pin = SENSOR_PIN,
               int airValue = SENSOR_AIR_VALUE,
               int waterValue = SENSOR_WATER_VALUE);

    void           begin();
    SensorReading  read();

    // Calibration helpers
    void setAirValue(int v)   { _airValue = v; }
    void setWaterValue(int v) { _waterValue = v; }
    int  getAirValue() const  { return _airValue; }
    int  getWaterValue() const { return _waterValue; }

private:
    uint8_t _pin;
    int     _airValue;
    int     _waterValue;

    int  _readRaw();
    float _rawToPercent(int raw);
};

#endif // SENSOR_H
