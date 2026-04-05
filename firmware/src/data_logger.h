/*
 * data_logger.h
 * Ring-buffer data logger that keeps readings in RAM and serves them as JSON
 */

#ifndef DATA_LOGGER_H
#define DATA_LOGGER_H

#include <Arduino.h>
#include "sensor.h"
#include "config.h"

class DataLogger {
public:
    DataLogger(size_t capacity = LOG_BUFFER_SIZE);
    ~DataLogger();

    /// Append a new reading to the ring buffer.
    void           addReading(const SensorReading& r);

    /// Number of readings currently stored.
    size_t         count() const;

    /// Get a reading by index (0 = oldest).
    SensorReading  get(size_t index) const;

    /// Serialize all stored readings to a JSON string.
    String         toJSON() const;

    /// Serialize only the latest reading to JSON.
    String         latestJSON() const;

    /// Clear all stored readings.
    void           clear();

private:
    SensorReading* _buf;
    size_t         _capacity;
    size_t         _head;   // next write position
    size_t         _count;
};

#endif // DATA_LOGGER_H
