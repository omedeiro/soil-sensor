/*
 * wifi_manager.cpp
 * WiFi connection management implementation with power management tuning
 */

#include "wifi_manager.h"



WifiConnection::WifiConnection() {}

bool WifiConnection::connect() {
    Serial.println(F("[WiFi] Starting connection…"));

    // Set a timeout so the captive portal doesn't block forever
    _wm.setConfigPortalTimeout(180);
    _wm.setConnectTimeout(60);  // Increased timeout for slower networks

    // If hardcoded credentials are provided, bypass WiFiManager entirely.
    if (strlen(WIFI_SSID) > 0) {
        Serial.println(F("[WiFi] Using hardcoded credentials"));
        // Persist credentials in SDK flash so WiFi.reconnect() works after
        // disconnects, and don't erase them (disconnect(false)).
        WiFi.persistent(true);
        WiFi.mode(WIFI_STA);
        WiFi.disconnect(false);
        delay(500);

        // Scan to confirm the target network is visible
        Serial.println(F("[WiFi] Scanning for networks..."));
        int n = WiFi.scanNetworks();
        bool found = false;
        for (int i = 0; i < n; i++) {
            Serial.print(F("  Found: "));
            Serial.print(WiFi.SSID(i));
            Serial.print(F(" ("));
            Serial.print(WiFi.RSSI(i));
            Serial.println(F(" dBm)"));
            if (WiFi.SSID(i) == String(WIFI_SSID)) found = true;
        }
        if (!found) {
            Serial.print(F("[WiFi] ✗ SSID '"));
            Serial.print(WIFI_SSID);
            Serial.println(F("' not found in scan — check name/band"));
        }
        WiFi.scanDelete();

        // Try connecting up to 3 times, using WiFi.localIP() for detection
        // (WiFi.status() can return non-standard values like 7 on some
        // ESP8266 revisions even when the connection succeeds).
#if USE_STATIC_IP
        {
            IPAddress ip, gw, sn, dns1, dns2;
            ip.fromString(STATIC_IP);
            gw.fromString(STATIC_GATEWAY);
            sn.fromString(STATIC_SUBNET);
            dns1.fromString(STATIC_DNS1);
            dns2.fromString(STATIC_DNS2);
            WiFi.config(ip, gw, sn, dns1, dns2);
            Serial.printf("[WiFi] Static IP configured: %s\n", STATIC_IP);
        }
#endif
        bool connected = false;
        for (int attempt = 1; attempt <= 3 && !connected; attempt++) {
            Serial.print(F("[WiFi] Attempt "));
            Serial.print(attempt);
            Serial.print(F("/3 connecting to "));
            Serial.println(WIFI_SSID);
            WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
            unsigned long start = millis();
            while (millis() - start < (unsigned long)WIFI_CONNECT_TIMEOUT * 1000UL / 3) {
                delay(500);
                Serial.print('.');
                yield();
#if USE_STATIC_IP
                // With a static IP, localIP().isSet() is true even without a
                // real association — require WL_CONNECTED.
                if (WiFi.status() == WL_CONNECTED) {
#else
                // With DHCP, an assigned IP proves a real association (and
                // tolerates ESP8266 revisions that report status 7 while
                // actually connected).
                if (WiFi.localIP().isSet()) {
#endif
                    connected = true;
                    break;
                }
            }
            if (!connected) {
                Serial.println();
                Serial.print(F("[WiFi] Attempt failed — status="));
                Serial.print(WiFi.status());
                Serial.print(F("  ip="));
                Serial.println(WiFi.localIP());
                WiFi.disconnect(false);
                delay(1000);
            }
        }
        Serial.println();
        if (connected) {
            Serial.print(F("[WiFi] ✓ Connected! IP: "));
            Serial.println(WiFi.localIP());
            Serial.print(F("[WiFi] Signal: "));
            Serial.print(WiFi.RSSI());
            Serial.println(F(" dBm"));
            WiFi.setSleepMode(WIFI_NONE_SLEEP);
            WiFi.setOutputPower(20.5);
            WiFi.setAutoReconnect(true);
            WiFi.persistent(true);
            Serial.println(F("[WiFi] Power management configured for stability"));
            return true;
        }
        Serial.println(F("[WiFi] Hardcoded credentials failed — will keep retrying in background"));
        // Do NOT fall through to the WiFiManager captive portal: it blocks for
        // up to 180 s and is useless when credentials are known (e.g. the
        // router is still rebooting after a power outage). Return false and
        // let the WiFi stability manager retry with backoff / restart.
        WiFi.mode(WIFI_STA);
        WiFi.begin(WIFI_SSID, WIFI_PASSWORD);  // keep SDK trying in background
        return false;
    }

    // No hardcoded credentials — use WiFiManager captive portal flow
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
        
        // Set DTIM listen interval (not available in newer SDK versions, skipped)
        Serial.println(F("[WiFi] DTIM listen interval: default"));
        
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
                WiFi.setAutoReconnect(true);
            }
        }
    }
    return connected;
}

bool WifiConnection::isConnected() {
#if USE_STATIC_IP
    // With a static IP, localIP().isSet() is true even when the device never
    // associated with the router — require WL_CONNECTED.
    return WiFi.status() == WL_CONNECTED;
#else
    // Some ESP8266 revisions report status 7 even when connected.
    // With DHCP, an assigned IP proves a real association.
    return WiFi.status() == WL_CONNECTED || WiFi.localIP().isSet();
#endif
}

String WifiConnection::localIP() {
    return WiFi.localIP().toString();
}

void WifiConnection::resetSettings() {
    _wm.resetSettings();
    Serial.println(F("[WiFi] Saved credentials erased"));
}
