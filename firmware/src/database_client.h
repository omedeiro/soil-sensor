/*
 * database_client.h
 * HTTP client for sending sensor readings to InfluxDB
 */

#ifndef DATABASE_CLIENT_H
#define DATABASE_CLIENT_H

#include <Arduino.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClient.h>
#include "config.h"
#include "reading_queue.h"

class DatabaseClient {
public:
    DatabaseClient();
    
    /**
     * Send a sensor reading to InfluxDB
     * 
     * @param deviceId Unique identifier for this sensor
     * @param timestamp Unix timestamp of the reading
     * @param raw Raw ADC value (0-1023)
     * @param moisture Calculated moisture percentage (0-100)
     * @param uptime Device uptime in seconds
     * @param crashes Crash counter
     * @param rssi WiFi signal strength in dBm
     * @param freeHeap Free heap memory in bytes
     * @param queueOnFail If true, add to queue on failure
     * @return true if successful, false otherwise
     */
    bool sendReading(
        const String& deviceId,
        unsigned long timestamp,
        int raw,
        float moisture,
        unsigned long uptime,
        int crashes,
        int rssi,
        int freeHeap,
        bool queueOnFail = true
    );

    /**
     * Send an ambient climate (DHT22) reading to InfluxDB.
     * Writes to the CLIMATE_MEASUREMENT measurement with temperature_c,
     * temperature_f and humidity float fields plus diagnostics.
     *
     * @param deviceId Unique identifier for this sensor
     * @param timestamp Unix timestamp of the reading
     * @param temperatureC Temperature in degrees Celsius
     * @param temperatureF Temperature in degrees Fahrenheit
     * @param humidity Relative humidity percentage (0-100)
     * @param uptime Device uptime in seconds
     * @param rssi WiFi signal strength in dBm
     * @param freeHeap Free heap memory in bytes
     * @param queueOnFail If true, add to queue on failure
     * @return true if successful, false otherwise
     */
    bool sendClimateReading(
        const String& deviceId,
        unsigned long timestamp,
        float temperatureC,
        float temperatureF,
        float humidity,
        unsigned long uptime,
        int rssi,
        int freeHeap,
        bool queueOnFail = true
    );
    
    /**
     * Attempt to drain the reading queue (non-blocking with time limit)
     * @param queue The queue to drain
     * @param maxTimeMs Maximum time to spend draining (default: MAX_DRAIN_TIME_MS)
     * @param maxReadings Maximum readings to drain in this call (default: MAX_DRAIN_PER_LOOP)
     * @return Number of readings successfully sent
     */
    int drainQueue(ReadingQueue& queue, unsigned long maxTimeMs = MAX_DRAIN_TIME_MS, int maxReadings = MAX_DRAIN_PER_LOOP);
    
    /**
     * Get the device ID (either auto-generated from MAC or custom)
     * @return Device ID string
     */
    static String getDeviceId();

private:
    WiFiClient wifiClient;
    HTTPClient http;
    
    /**
     * Convert MAC address to hex string
     * @return MAC address as string (e.g., "40915141d997")
     */
    static String getMacAddress();
    
    /**
     * Build InfluxDB line protocol string
     */
    String buildLineProtocol(
        const String& deviceId,
        unsigned long timestamp,
        int raw,
        float moisture,
        unsigned long uptime,
        int crashes,
        int rssi,
        int freeHeap
    );

    /**
     * Build InfluxDB line protocol string for a climate (DHT22) reading
     */
    String buildClimateLineProtocol(
        const String& deviceId,
        unsigned long timestamp,
        float temperatureC,
        float temperatureF,
        float humidity,
        unsigned long uptime,
        int rssi,
        int freeHeap
    );
    
    /**
     * Send data to InfluxDB with retry logic
     * @param payload InfluxDB line protocol string
     * @param maxRetries Maximum number of retry attempts
     * @return true if successful
     */
    bool postToInflux(const String& payload, int maxRetries = 3);
};

#endif // DATABASE_CLIENT_H
