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
     * Attempt to drain the reading queue
     * @param queue The queue to drain
     * @return Number of readings successfully sent
     */
    int drainQueue(ReadingQueue& queue);
    
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
     * Send data to InfluxDB with retry logic
     * @param payload InfluxDB line protocol string
     * @param maxRetries Maximum number of retry attempts
     * @return true if successful
     */
    bool postToInflux(const String& payload, int maxRetries = 3);
};

#endif // DATABASE_CLIENT_H
