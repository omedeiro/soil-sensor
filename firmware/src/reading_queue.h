/*
 * reading_queue.h
 * Queue for failed sensor readings to be retried when connection restored
 */

#ifndef READING_QUEUE_H
#define READING_QUEUE_H

#include <Arduino.h>

#define QUEUE_MAX_SIZE 20  // Store up to 20 failed readings

struct QueuedReading {
    String deviceId;
    unsigned long timestamp;
    int raw;
    float moisture;
    unsigned long uptime;
    int crashes;
    int rssi;
    int freeHeap;
};

class ReadingQueue {
public:
    ReadingQueue();
    
    // Add reading to queue (returns false if queue is full)
    bool enqueue(const QueuedReading& reading);
    
    // Remove and return oldest reading (returns false if queue is empty)
    bool dequeue(QueuedReading& reading);
    
    // Peek at oldest reading without removing
    bool peek(QueuedReading& reading);
    
    // Check if queue is empty
    bool isEmpty();
    
    // Check if queue is full
    bool isFull();
    
    // Get current size
    size_t count();
    
    // Clear all queued readings
    void clear();
    
    // Print queue status
    void printStatus();
    
private:
    QueuedReading queue[QUEUE_MAX_SIZE];
    size_t head;  // Next write position
    size_t tail;  // Next read position
    size_t size;  // Current number of items
};

#endif // READING_QUEUE_H
