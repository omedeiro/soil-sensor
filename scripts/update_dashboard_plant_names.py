#!/usr/bin/env python3
"""
Update Grafana dashboards with plant names for each sensor.
Version 2.6.0 - Add plant type information to sensor labels.
"""

import json
import sys
from pathlib import Path

# Plant mapping: sensor-id -> (location, plant_name)
PLANT_MAP = {
    "sensor-1": ("Bed Room", "Rubber Tree"),
    "sensor-2": ("Living Room", "Monstera"),
    "sensor-3": ("Living Room", "Avocado"),  # Location updated from Guest Room
    "sensor-4": ("Guest Room", "Micro Greens"),
    "sensor-5": ("Bed Room", "ZZ Plant"),
    "sensor-6": ("Living Room", "Ficus Elastica Ruby"),
    "sensor-7": ("Guest Room", "Basil - pot"),
}

def update_sensor_options(dashboard_data):
    """Update sensor dropdown options with plant names."""
    templating = dashboard_data.get("templating", {})
    variables = templating.get("list", [])
    
    for var in variables:
        if var.get("name") == "sensor":
            # Update description
            var["description"] = "Select sensor to view (with plant types)"
            
            # Update options
            options = var.get("options", [])
            updated_options = []
            
            for opt in options:
                # Keep "All" option as-is
                if opt.get("value") == "$__all":
                    updated_options.append(opt)
                    continue
                
                # Update sensor options with plant names
                sensor_id = opt.get("value", "")
                if sensor_id in PLANT_MAP:
                    location, plant = PLANT_MAP[sensor_id]
                    sensor_num = sensor_id.split("-")[1]
                    opt["text"] = f"Sensor {sensor_num} ({location}, {plant})"
                    updated_options.append(opt)
                else:
                    # Keep unknown sensors as-is
                    updated_options.append(opt)
            
            var["options"] = updated_options
            print(f"  ✓ Updated sensor dropdown with {len(updated_options)-1} sensors")
            return True
    
    return False

def update_dashboard_file(filepath):
    """Update a single dashboard JSON file."""
    print(f"\nProcessing: {filepath.name}")
    
    try:
        with open(filepath, 'r') as f:
            dashboard = json.load(f)
        
        # Update sensor options
        updated = update_sensor_options(dashboard)
        
        if updated:
            # Write back to file
            with open(filepath, 'w') as f:
                json.dump(dashboard, f, indent=2)
            print(f"  ✓ Saved changes to {filepath.name}")
            return True
        else:
            print(f"  ⚠ No sensor variable found in {filepath.name}")
            return False
            
    except Exception as e:
        print(f"  ✗ Error processing {filepath.name}: {e}")
        return False

def main():
    """Update all Grafana dashboards with plant names."""
    dashboards_dir = Path("/Users/owenmedeiros/soil-sensor/grafana-dashboards")
    
    # Dashboards that have sensor dropdowns
    target_dashboards = [
        "sensor-explorer.json",
        "sensor-details.json",
        "alerts-overview.json",
        "mobile-summary.json",
    ]
    
    print("=" * 60)
    print("Updating Grafana Dashboards with Plant Names (v2.6.0)")
    print("=" * 60)
    
    success_count = 0
    for dashboard_name in target_dashboards:
        filepath = dashboards_dir / dashboard_name
        if filepath.exists():
            if update_dashboard_file(filepath):
                success_count += 1
        else:
            print(f"\n⚠ Dashboard not found: {dashboard_name}")
    
    print("\n" + "=" * 60)
    print(f"✓ Updated {success_count}/{len(target_dashboards)} dashboards")
    print("=" * 60)
    
    return 0 if success_count == len(target_dashboards) else 1

if __name__ == "__main__":
    sys.exit(main())
