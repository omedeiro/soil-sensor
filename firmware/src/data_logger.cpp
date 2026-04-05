/*
 * data_logger.cpp
 * Ring-buffer data logger implementation
 */

#include "data_logger.h"
#include <ArduinoJson.h>

DataLogger::DataLogger(size_t capacity)
    : _capacity(capacity), _head(0), _count(0) {
    _buf = new SensorReading[capacity];
}

DataLogger::~DataLogger() {
    delete[] _buf;
}

void DataLogger::addReading(const SensorReading& r) {
    _buf[_head] = r;
    _head = (_head + 1) % _capacity;
    if (_count < _capacity) _count++;
}

size_t DataLogger::count() const {
    return _count;
}

SensorReading DataLogger::get(size_t index) const {
    // Oldest entry lives at (_head - _count + _capacity) % _capacity
    size_t pos = (_head - _count + index + _capacity) % _capacity;
    return _buf[pos];
}

String DataLogger::toJSON() const {
    // Stream the JSON directly to a String to keep memory low.
    String out;
    out.reserve(_count * 48 + 32);
    out += F("{\"count\":");
    out += String(_count);
    out += F(",\"readings\":[");

    for (size_t i = 0; i < _count; i++) {
        SensorReading r = get(i);
        if (i > 0) out += ',';
        out += F("{\"ts\":");
        out += String(r.timestamp);
        out += F(",\"raw\":");
        out += String(r.rawValue);
        out += F(",\"moisture\":");
        out += String(r.moisturePct, 1);
        out += '}';
    }
    out += F("]}");
    return out;
}

String DataLogger::latestJSON() const {
    if (_count == 0) return F("{\"error\":\"no data\"}");
    SensorReading r = get(_count - 1);
    String out;
    out += F("{\"ts\":");
    out += String(r.timestamp);
    out += F(",\"raw\":");
    out += String(r.rawValue);
    out += F(",\"moisture\":");
    out += String(r.moisturePct, 1);
    out += '}';
    return out;
}

void DataLogger::clear() {
    _head  = 0;
    _count = 0;
}
