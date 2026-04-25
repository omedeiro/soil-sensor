/*
 * database_client.h
 * HTTP client for sending sensor readings to remote database
 */

#ifndef DATABASE_CLIENT_H
#define DATABASE_CLIENT_H

#include <Arduino.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClient.h>
#include "config.h"

class DatabaseClient {
public:
    DatabaseClient();
    
    /**
     * Send a sensor reading to the database server
     * 
     * @param deviceId Unique identifier for this sensor
     * @param timestamp Unix timestamp of the reading
     * @param raw Raw ADC value (0-1023)
     * @param moisture Calculated moisture percentage (0-100)
     * @param uptime Device uptime in seconds
     * @param crashes Crash counter
     * @return true if successful, false otherwise
     */
    bool sendReading(
        const String& deviceId,
        unsigned long timestamp,
        int raw,
        float moisture,
        unsigned long uptime = 0,
        int crashes = 0
    );
    
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
};

#endif // DATABASE_CLIENT_H
