/*
 * dht_sensor.h
 * DHT22 / AM2302 ambient temperature + humidity sensor driver.
 * Mirrors the SoilSensor interface so main.cpp can swap between them.
 */

#ifndef DHT_SENSOR_H
#define DHT_SENSOR_H

#include <Arduino.h>
#include <DHT.h>
#include "config.h"

struct ClimateReading {
    unsigned long timestamp;    // epoch seconds (from NTP)
    float         temperatureC; // °C (native DHT22 reading)
    float         temperatureF; // °F (converted)
    float         humidity;     // relative humidity %
    bool          valid;        // false if the DHT returned NaN
};

class DHTSensor {
public:
    DHTSensor(uint8_t pin = DHT_PIN, uint8_t type = DHT_TYPE);

    void          begin();
    ClimateReading read();

private:
    DHT     _dht;
    uint8_t _pin;
};

#endif // DHT_SENSOR_H
