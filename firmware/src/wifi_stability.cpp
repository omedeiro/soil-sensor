/*
 * wifi_stability.cpp
 * WiFi stability manager implementation
 */

#include "wifi_stability.h"

// Static member initialization
unsigned long WiFiStabilityManager::lastConnectTime = 0;
unsigned long WiFiStabilityManager::lastDisconnectTime = 0;
unsigned long WiFiStabilityManager::totalDisconnects = 0;
uint8_t WiFiStabilityManager::lastDisconnectReason = 0;

WiFiStabilityManager::WiFiStabilityManager()
    : reconnectDelay(MIN_RECONNECT_DELAY),
      nextReconnectTime(0),
      reconnectAttempts(0),
      isReconnecting(false) {
}

void WiFiStabilityManager::begin() {
    // Register WiFi event handlers
    static WiFiEventHandler connectHandler;
    static WiFiEventHandler disconnectHandler;
    
    connectHandler = WiFi.onStationModeGotIP(onWiFiConnect);
    disconnectHandler = WiFi.onStationModeDisconnected(onWiFiDisconnect);
    
    Serial.println(F("[WiFi-Stability] Event handlers registered"));
}

void WiFiStabilityManager::onWiFiConnect(const WiFiEventStationModeGotIP& event) {
    lastConnectTime = millis();
    
    Serial.println(F("─────────────────────────────────────"));
    Serial.println(F("📡 WiFi Connected Event"));
    Serial.print(F("  IP Address: "));
    Serial.println(event.ip);
    Serial.print(F("  Gateway: "));
    Serial.println(event.gw);
    Serial.print(F("  Subnet: "));
    Serial.println(event.mask);
    Serial.println(F("─────────────────────────────────────"));
}

void WiFiStabilityManager::onWiFiDisconnect(const WiFiEventStationModeDisconnected& event) {
    lastDisconnectTime = millis();
    totalDisconnects++;
    lastDisconnectReason = event.reason;
    
    Serial.println(F("─────────────────────────────────────"));
    Serial.println(F("⚠️  WiFi Disconnected Event"));
    Serial.print(F("  SSID: "));
    Serial.println(event.ssid);
    Serial.print(F("  Reason Code: "));
    Serial.print(event.reason);
    Serial.print(F(" - "));
    
    // Decode common disconnect reasons
    switch(event.reason) {
        case REASON_UNSPECIFIED:
            Serial.println(F("Unspecified"));
            break;
        case REASON_AUTH_EXPIRE:
            Serial.println(F("Auth Expired"));
            break;
        case REASON_AUTH_LEAVE:
            Serial.println(F("Auth Leave"));
            break;
        case REASON_ASSOC_EXPIRE:
            Serial.println(F("Association Expired"));
            break;
        case REASON_ASSOC_TOOMANY:
            Serial.println(F("Too Many Associations"));
            break;
        case REASON_NOT_AUTHED:
            Serial.println(F("Not Authenticated"));
            break;
        case REASON_NOT_ASSOCED:
            Serial.println(F("Not Associated"));
            break;
        case REASON_ASSOC_LEAVE:
            Serial.println(F("Association Leave"));
            break;
        case REASON_ASSOC_NOT_AUTHED:
            Serial.println(F("Association Not Authenticated"));
            break;
        case REASON_DISASSOC_PWRCAP_BAD:
            Serial.println(F("Disassociated - Power Capability Bad"));
            break;
        case REASON_DISASSOC_SUPCHAN_BAD:
            Serial.println(F("Disassociated - Supported Channel Bad"));
            break;
        case REASON_IE_INVALID:
            Serial.println(F("Invalid IE"));
            break;
        case REASON_MIC_FAILURE:
            Serial.println(F("MIC Failure"));
            break;
        case REASON_4WAY_HANDSHAKE_TIMEOUT:
            Serial.println(F("4-Way Handshake Timeout"));
            break;
        case REASON_GROUP_KEY_UPDATE_TIMEOUT:
            Serial.println(F("Group Key Update Timeout"));
            break;
        case REASON_IE_IN_4WAY_DIFFERS:
            Serial.println(F("IE in 4-Way Differs"));
            break;
        case REASON_GROUP_CIPHER_INVALID:
            Serial.println(F("Group Cipher Invalid"));
            break;
        case REASON_PAIRWISE_CIPHER_INVALID:
            Serial.println(F("Pairwise Cipher Invalid"));
            break;
        case REASON_AKMP_INVALID:
            Serial.println(F("AKMP Invalid"));
            break;
        case REASON_UNSUPP_RSN_IE_VERSION:
            Serial.println(F("Unsupported RSN IE Version"));
            break;
        case REASON_INVALID_RSN_IE_CAP:
            Serial.println(F("Invalid RSN IE Capability"));
            break;
        case REASON_802_1X_AUTH_FAILED:
            Serial.println(F("802.1X Auth Failed"));
            break;
        case REASON_CIPHER_SUITE_REJECTED:
            Serial.println(F("Cipher Suite Rejected"));
            break;
        case REASON_BEACON_TIMEOUT:
            Serial.println(F("Beacon Timeout - Weak Signal"));
            break;
        case REASON_NO_AP_FOUND:
            Serial.println(F("No AP Found"));
            break;
        case REASON_AUTH_FAIL:
            Serial.println(F("Authentication Failed"));
            break;
        case REASON_ASSOC_FAIL:
            Serial.println(F("Association Failed"));
            break;
        case REASON_HANDSHAKE_TIMEOUT:
            Serial.println(F("Handshake Timeout"));
            break;
        default:
            Serial.println(F("Unknown"));
            break;
    }
    
    Serial.print(F("  Total Disconnects: "));
    Serial.println(totalDisconnects);
    Serial.println(F("─────────────────────────────────────"));
}

void WiFiStabilityManager::loop() {
    // Only run reconnection logic if disconnected
    // Use IP fallback for ESP8266 revisions that return non-standard status codes
    if (!(WiFi.status() == WL_CONNECTED || WiFi.localIP().isSet())) {
        if (!isReconnecting && millis() >= nextReconnectTime) {
            attemptReconnect();
        }
    } else {
        // Connected - check if we should reset the backoff timer
        unsigned long connectedDuration = millis() - lastConnectTime;
        
        if (isReconnecting && connectedDuration > STABLE_CONNECTION_TIME) {
            // Been stable for 5 minutes, reset reconnection state
            Serial.println(F("[WiFi-Stability] Connection stable, resetting backoff"));
            reconnectDelay = MIN_RECONNECT_DELAY;
            reconnectAttempts = 0;
            isReconnecting = false;
        }
    }
}

void WiFiStabilityManager::attemptReconnect() {
    reconnectAttempts++;
    isReconnecting = true;
    
    Serial.println(F("─────────────────────────────────────"));
    Serial.printf("[WiFi-Stability] Reconnection Attempt #%u\n", reconnectAttempts);
    Serial.printf("  Backoff delay: %lu ms\n", reconnectDelay);
    Serial.printf("  Last disconnect reason: %u\n", lastDisconnectReason);
    
    // Check if too many consecutive failures
    if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
        Serial.println(F("  ⚠️  Too many failed attempts - forcing full WiFi reset"));
        WiFi.disconnect();
        delay(1000);
        ESP.restart();  // Nuclear option: full restart
    }
    
    // Attempt reconnection
    WiFi.reconnect();
    
    // Calculate next reconnect time with exponential backoff
    reconnectDelay = min(reconnectDelay * 2, MAX_RECONNECT_DELAY);
    nextReconnectTime = millis() + reconnectDelay;
    
    Serial.printf("  Next attempt in: %lu ms\n", reconnectDelay);
    Serial.println(F("─────────────────────────────────────"));
}

bool WiFiStabilityManager::isHealthy() {
    // Consider healthy if:
    // 1. Connected, OR
    // 2. Attempting to reconnect and haven't exceeded max attempts
    return (WiFi.status() == WL_CONNECTED || WiFi.localIP().isSet()) || 
           (isReconnecting && reconnectAttempts < MAX_RECONNECT_ATTEMPTS);
}

unsigned long WiFiStabilityManager::getConnectedTime() {
    if ((WiFi.status() == WL_CONNECTED || WiFi.localIP().isSet()) && lastConnectTime > 0) {
        return millis() - lastConnectTime;
    }
    return 0;
}

unsigned long WiFiStabilityManager::getDisconnectedTime() {
    if (!(WiFi.status() == WL_CONNECTED || WiFi.localIP().isSet()) && lastDisconnectTime > 0) {
        return millis() - lastDisconnectTime;
    }
    return 0;
}

unsigned long WiFiStabilityManager::getTotalDisconnects() {
    return totalDisconnects;
}

uint8_t WiFiStabilityManager::getLastDisconnectReason() {
    return lastDisconnectReason;
}

uint16_t WiFiStabilityManager::getReconnectAttempts() {
    return reconnectAttempts;
}

void WiFiStabilityManager::printDiagnostics() {
    Serial.println(F("═══════════════════════════════════════"));
    Serial.println(F("📡 WiFi Stability Diagnostics"));
    Serial.println(F("═══════════════════════════════════════"));
    
    Serial.print(F("Status: "));
    if (WiFi.status() == WL_CONNECTED || WiFi.localIP().isSet()) {
        Serial.println(F("CONNECTED"));
        Serial.print(F("  Connected for: "));
        Serial.print(getConnectedTime() / 1000);
        Serial.println(F(" seconds"));
    } else {
        Serial.println(F("DISCONNECTED"));
        Serial.print(F("  Disconnected for: "));
        Serial.print(getDisconnectedTime() / 1000);
        Serial.println(F(" seconds"));
        Serial.print(F("  Reconnect attempts: "));
        Serial.println(reconnectAttempts);
    }
    
    Serial.print(F("Total disconnects: "));
    Serial.println(totalDisconnects);
    
    Serial.print(F("Last disconnect reason: "));
    Serial.println(lastDisconnectReason);
    
    if (WiFi.status() == WL_CONNECTED || WiFi.localIP().isSet()) {
        Serial.print(F("SSID: "));
        Serial.println(WiFi.SSID());
        
        Serial.print(F("BSSID: "));
        Serial.println(WiFi.BSSIDstr());
        
        Serial.print(F("Channel: "));
        Serial.println(WiFi.channel());
        
        Serial.print(F("RSSI: "));
        Serial.print(WiFi.RSSI());
        Serial.println(F(" dBm"));
        
        Serial.print(F("IP Address: "));
        Serial.println(WiFi.localIP());
    }
    
    Serial.println(F("═══════════════════════════════════════"));
}
