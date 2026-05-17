#!/usr/bin/env python3
"""
system-metrics-collector.py
Collects Raspberry Pi system metrics and sends to InfluxDB
Runs every 60 seconds via systemd timer
"""

import psutil
import time
import os
import socket
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS

# Configuration - read from environment variables
INFLUX_URL = os.getenv('INFLUX_URL', 'http://localhost:8086')
INFLUX_TOKEN = os.getenv('INFLUX_TOKEN', '')
INFLUX_ORG = os.getenv('INFLUX_ORG', 'soil-monitoring')
INFLUX_BUCKET = os.getenv('INFLUX_BUCKET', 'sensor-readings')

# Get hostname
HOSTNAME = socket.gethostname()

def get_cpu_temperature():
    """Get CPU temperature in Celsius (Raspberry Pi specific)"""
    try:
        # Raspberry Pi thermal zone
        with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
            temp = float(f.read().strip()) / 1000.0
            return temp
    except:
        return None

def collect_metrics():
    """Collect all system metrics"""
    metrics = {}
    
    # CPU metrics
    metrics['cpu_percent'] = psutil.cpu_percent(interval=1)
    metrics['cpu_temp'] = get_cpu_temperature()
    
    # Load averages
    load_avg = os.getloadavg()
    metrics['load_1min'] = load_avg[0]
    metrics['load_5min'] = load_avg[1]
    metrics['load_15min'] = load_avg[2]
    
    # Memory metrics
    mem = psutil.virtual_memory()
    metrics['ram_used_mb'] = mem.used / (1024 * 1024)
    metrics['ram_free_mb'] = mem.available / (1024 * 1024)
    metrics['ram_percent'] = mem.percent
    
    # Disk metrics for /mnt/sensor-data
    try:
        disk = psutil.disk_usage('/mnt/sensor-data')
        metrics['disk_used_gb'] = disk.used / (1024 * 1024 * 1024)
        metrics['disk_free_gb'] = disk.free / (1024 * 1024 * 1024)
        metrics['disk_percent'] = disk.percent
    except:
        # Fallback to root filesystem
        disk = psutil.disk_usage('/')
        metrics['disk_used_gb'] = disk.used / (1024 * 1024 * 1024)
        metrics['disk_free_gb'] = disk.free / (1024 * 1024 * 1024)
        metrics['disk_percent'] = disk.percent
    
    # Uptime
    metrics['uptime_seconds'] = int(time.time() - psutil.boot_time())
    
    return metrics

def send_to_influxdb(metrics):
    """Send metrics to InfluxDB"""
    if not INFLUX_TOKEN:
        print("ERROR: INFLUX_TOKEN not set")
        return False
    
    try:
        # Create InfluxDB client
        client = InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG)
        write_api = client.write_api(write_options=SYNCHRONOUS)
        
        # Build point
        point = Point("rpi_system_metrics") \
            .tag("hostname", HOSTNAME) \
            .field("cpu_percent", metrics['cpu_percent']) \
            .field("load_1min", metrics['load_1min']) \
            .field("load_5min", metrics['load_5min']) \
            .field("load_15min", metrics['load_15min']) \
            .field("ram_used_mb", metrics['ram_used_mb']) \
            .field("ram_free_mb", metrics['ram_free_mb']) \
            .field("ram_percent", metrics['ram_percent']) \
            .field("disk_used_gb", metrics['disk_used_gb']) \
            .field("disk_free_gb", metrics['disk_free_gb']) \
            .field("disk_percent", metrics['disk_percent']) \
            .field("uptime_seconds", metrics['uptime_seconds'])
        
        # Add CPU temperature if available
        if metrics['cpu_temp'] is not None:
            point.field("cpu_temp", metrics['cpu_temp'])
        
        # Write to InfluxDB
        write_api.write(bucket=INFLUX_BUCKET, record=point)
        client.close()
        
        print(f"✓ Sent metrics: CPU={metrics['cpu_percent']:.1f}%, Temp={metrics['cpu_temp']:.1f}°C, RAM={metrics['ram_percent']:.1f}%, Disk={metrics['disk_percent']:.1f}%")
        return True
        
    except Exception as e:
        print(f"✗ Failed to send metrics: {e}")
        return False

def main():
    """Main entry point"""
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Collecting system metrics for {HOSTNAME}...")
    
    # Collect metrics
    metrics = collect_metrics()
    
    # Send to InfluxDB
    send_to_influxdb(metrics)

if __name__ == '__main__':
    main()
