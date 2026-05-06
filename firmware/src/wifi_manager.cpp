/*
 * wifi_manager.cpp
 * WiFi connection management implementation with power management tuning
 */

#include "wifi_manager.h"

extern "C" {
    #include "user_interface.h"  // For wifi_set_listen_interval
}

WifiConnection::WifiConnection() {}

bool WifiConnection::connect() {
    Serial.println(F("[WiFi] Starting connection…"));

    // Set a timeout so the captive portal doesn't block forever
    _wm.setConfigPortalTimeout(180);
    _wm.setConnectTimeout(60);  // Increased timeout for slower networks

    // Try to auto-connect with saved credentials.
    // If that fails, start the captive-portal AP.
    bool connected;
    if (strlen(AP_PASSWORD) > 0) {
        connected = _wm.autoConnect(AP_NAME, AP_PASSWORD);
    } else {
        connected = _wm.autoConnect(AP_NAME);
    }

    if (connected) {
        Serial.print(F("[WiFi] ✓ Connected! IP: "));
        Serial.println(WiFi.localIP());
        Serial.print(F("[WiFi] SSID: "));
        Serial.println(WiFi.SSID());
        Serial.print(F("[WiFi] Signal: "));
        Serial.print(WiFi.RSSI());
        Serial.println(F(" dBm"));
        
        // ═══════════════════════════════════════════════════════════════
        // WiFi Stability Power Management Tuning
        // ═══════════════════════════════════════════════════════════════
        
        // Disable WiFi sleep for maximum stability
        // Trade-off: Higher power consumption for better reliability
        WiFi.setSleepMode(WIFI_NONE_SLEEP);
        Serial.println(F("[WiFi] Sleep mode: DISABLED (max stability)"));
        
        // Set maximum output power (helps with weak signal scenarios)
        WiFi.setOutputPower(20.5);  // Max for ESP8266 is 20.5 dBm
        Serial.println(F("[WiFi] Output power: 20.5 dBm (maximum)"));
        
        // Set DTIM listen interval
        // Lower value = more battery drain, but more stable connection
        // Value of 3 = listen every 3 beacons (good balance)
        wifi_set_listen_interval(3);
        Serial.println(F("[WiFi] DTIM listen interval: 3 (stable mode)"));
        
        // Enable auto-reconnect (ESP8266 will try to reconnect automatically)
        WiFi.setAutoReconnect(true);
        Serial.println(F("[WiFi] Auto-reconnect: ENABLED"));
        
        // Set persistent WiFi credentials (survive reboot)
        WiFi.persistent(true);
        
        Serial.println(F("[WiFi] Power management configured for stability"));
        
    } else {
        Serial.println(F("[WiFi] Failed to connect (portal timed out)"));
        // Fallback: try hard-coded credentials if provided
        if (strlen(WIFI_SSID) > 0) {
            Serial.printf("[WiFi] Trying fallback SSID: %s\n", WIFI_SSID);
            WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
            unsigned long start = millis();
            while (WiFi.status() != WL_CONNECTED &&
                   millis() - start < (unsigned long)WIFI_CONNECT_TIMEOUT * 1000) {
                delay(500);
                Serial.print('.');
                yield();  // Feed watchdog
            }
            Serial.println();
            connected = WiFi.status() == WL_CONNECTED;
            if (connected) {
                Serial.print(F("[WiFi] ✓ Connected via fallback! IP: "));
                Serial.println(WiFi.localIP());
                
                // Apply same power management settings
                WiFi.setSleepMode(WIFI_NONE_SLEEP);
                WiFi.setOutputPower(20.5);
                wifi_set_listen_interval(3);
                WiFi.setAutoReconnect(true);
            }
        }
    }
    return connected;
}

bool WifiConnection::isConnected() {
    return WiFi.status() == WL_CONNECTED;
}

String WifiConnection::localIP() {
    return WiFi.localIP().toString();
}

void WifiConnection::resetSettings() {
    _wm.resetSettings();
    Serial.println(F("[WiFi] Saved credentials erased"));
}
