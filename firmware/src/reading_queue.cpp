/*
 * reading_queue.cpp
 * Queue implementation for failed sensor readings
 */

#include "reading_queue.h"

ReadingQueue::ReadingQueue() : head(0), tail(0), size(0) {
}

bool ReadingQueue::enqueue(const QueuedReading& reading) {
    if (isFull()) {
        Serial.println(F("[Queue] ✗ Queue is full, cannot enqueue"));
        return false;
    }
    
    queue[head] = reading;
    head = (head + 1) % QUEUE_MAX_SIZE;
    size++;
    
    Serial.printf("[Queue] ✓ Enqueued reading (queue size: %u/%u)\n", size, QUEUE_MAX_SIZE);
    return true;
}

bool ReadingQueue::dequeue(QueuedReading& reading) {
    if (isEmpty()) {
        return false;
    }
    
    reading = queue[tail];
    tail = (tail + 1) % QUEUE_MAX_SIZE;
    size--;
    
    return true;
}

bool ReadingQueue::peek(QueuedReading& reading) {
    if (isEmpty()) {
        return false;
    }
    
    reading = queue[tail];
    return true;
}

bool ReadingQueue::isEmpty() {
    return size == 0;
}

bool ReadingQueue::isFull() {
    return size >= QUEUE_MAX_SIZE;
}

size_t ReadingQueue::count() {
    return size;
}

void ReadingQueue::clear() {
    head = 0;
    tail = 0;
    size = 0;
    Serial.println(F("[Queue] Cleared all queued readings"));
}

void ReadingQueue::printStatus() {
    Serial.println(F("─────────────────────────────────────"));
    Serial.println(F("📦 Reading Queue Status"));
    Serial.printf("  Size: %u / %u\n", size, QUEUE_MAX_SIZE);
    
    if (size > 0) {
        Serial.println(F("  Oldest reading:"));
        QueuedReading oldest = queue[tail];
        Serial.printf("    Device: %s\n", oldest.deviceId.c_str());
        Serial.printf("    Timestamp: %lu\n", oldest.timestamp);
        Serial.printf("    Moisture: %.1f%%\n", oldest.moisture);
    } else {
        Serial.println(F("  Queue is empty"));
    }
    
    Serial.println(F("─────────────────────────────────────"));
}
