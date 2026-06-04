#!/usr/bin/env python3
"""
Validate sensors-config.json before generating dashboards.

Checks:
- Valid JSON syntax
- Required fields present
- Valid color codes
- Unique sensor IDs
- Valid threshold values
"""

import json
import re
import sys
from pathlib import Path


def validate_color(color):
    """Check if color is a valid hex code."""
    return bool(re.match(r'^#[0-9A-Fa-f]{6}$', color))


def validate_sensor(sensor, index):
    """Validate a single sensor configuration."""
    errors = []
    sensor_id = sensor.get('id', f'sensor-{index}')
    
    # Required fields
    required = ['id', 'plant', 'location', 'color', 'thresholds', 'colorSteps']
    for field in required:
        if field not in sensor:
            errors.append(f"{sensor_id}: Missing required field '{field}'")
    
    # Validate ID format
    if 'id' in sensor and not re.match(r'^sensor-\d+$', sensor['id']):
        errors.append(f"{sensor_id}: ID must be in format 'sensor-N' (e.g., 'sensor-1')")
    
    # Validate color
    if 'color' in sensor and not validate_color(sensor['color']):
        errors.append(f"{sensor_id}: Invalid color '{sensor['color']}' (must be #RRGGBB)")
    
    # Validate thresholds
    if 'thresholds' in sensor:
        thresholds = sensor['thresholds']
        if 'low' not in thresholds or 'medium' not in thresholds:
            errors.append(f"{sensor_id}: Thresholds must have 'low' and 'medium' values")
        else:
            if not (0 <= thresholds['low'] <= 100):
                errors.append(f"{sensor_id}: threshold.low must be 0-100")
            if not (0 <= thresholds['medium'] <= 100):
                errors.append(f"{sensor_id}: threshold.medium must be 0-100")
            if thresholds['low'] >= thresholds['medium']:
                errors.append(f"{sensor_id}: threshold.low must be < threshold.medium")
    
    # Validate colorSteps
    if 'colorSteps' in sensor:
        if not isinstance(sensor['colorSteps'], list) or len(sensor['colorSteps']) != 3:
            errors.append(f"{sensor_id}: colorSteps must be an array of 3 color stops")
        else:
            for i, step in enumerate(sensor['colorSteps']):
                if 'color' not in step or not validate_color(step['color']):
                    errors.append(f"{sensor_id}: colorSteps[{i}] has invalid color")
    
    return errors


def validate_config(config):
    """Validate entire configuration."""
    errors = []
    
    # Check top-level structure
    if 'sensors' not in config:
        return ["Missing 'sensors' array in config"]
    
    if 'grafana' not in config:
        errors.append("Missing 'grafana' configuration")
    
    # Validate sensors
    sensors = config['sensors']
    if not isinstance(sensors, list):
        return ["'sensors' must be an array"]
    
    if len(sensors) == 0:
        return ["No sensors defined in config"]
    
    # Check for duplicate IDs
    sensor_ids = [s.get('id') for s in sensors]
    duplicates = [sid for sid in sensor_ids if sensor_ids.count(sid) > 1]
    if duplicates:
        errors.append(f"Duplicate sensor IDs found: {set(duplicates)}")
    
    # Validate each sensor
    for i, sensor in enumerate(sensors):
        errors.extend(validate_sensor(sensor, i + 1))
    
    # Validate Grafana config
    if 'grafana' in config:
        grafana = config['grafana']
        required_grafana = ['influxdb_datasource_uid', 'bucket', 'measurement']
        for field in required_grafana:
            if field not in grafana:
                errors.append(f"Grafana config missing '{field}'")
    
    return errors


def main():
    """Main validation function."""
    config_file = Path(__file__).parent / "sensors-config.json"
    
    if not config_file.exists():
        print(f"✗ Configuration file not found: {config_file}")
        sys.exit(1)
    
    print(f"Validating {config_file}...")
    
    # Parse JSON
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
    except json.JSONDecodeError as e:
        print(f"✗ Invalid JSON syntax: {e}")
        sys.exit(1)
    
    # Validate configuration
    errors = validate_config(config)
    
    if errors:
        print(f"\n✗ Found {len(errors)} validation error(s):\n")
        for error in errors:
            print(f"  • {error}")
        sys.exit(1)
    
    # Success
    sensor_count = len(config['sensors'])
    print(f"✓ Configuration is valid ({sensor_count} sensors)")
    
    # Print summary
    print("\nSensors:")
    for sensor in config['sensors']:
        print(f"  {sensor['id']:10s} → {sensor['plant']:20s} ({sensor['location']})")
    
    print(f"\nGrafana datasource: {config['grafana']['influxdb_datasource_uid']}")
    print(f"InfluxDB bucket:    {config['grafana']['bucket']}")
    
    sys.exit(0)


if __name__ == "__main__":
    main()
