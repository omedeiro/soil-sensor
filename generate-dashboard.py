#!/usr/bin/env python3
"""
Generate Grafana dashboard from centralized sensor configuration.

This script reads sensors-config.json and generates the soil-moisture-main.json
dashboard file with all sensor configurations, labels, colors, and filters.

Usage:
    ./generate-dashboard.py
    
Output:
    grafana-dashboards/soil-moisture-main.json
"""

import json
import sys
from pathlib import Path


def load_config():
    """Load the centralized sensor configuration."""
    config_file = Path(__file__).parent / "sensors-config.json"
    with open(config_file, 'r') as f:
        return json.load(f)


def create_dropdown_options(sensors):
    """Create dropdown variable options from sensor config."""
    options = [
        {
            "text": "All",
            "value": "$__all",
            "selected": True
        }
    ]
    
    for sensor in sensors:
        options.append({
            "text": sensor["plant"],
            "value": sensor["id"],
            "selected": False
        })
    
    return options


def create_field_override(sensor, is_bargauge=False):
    """Create field override for a sensor with colors and display name."""
    override = {
        "matcher": {
            "id": "byRegexp",
            "options": f".*{sensor['id']}.*"
        },
        "properties": [
            {
                "id": "displayName",
                "value": sensor["plant"]
            }
        ]
    }
    
    # Bar gauge needs threshold-based colors
    if is_bargauge:
        override["properties"].extend([
            {
                "id": "thresholds",
                "value": {
                    "mode": "absolute",
                    "steps": sensor["colorSteps"]
                }
            },
            {
                "id": "color",
                "value": {
                    "mode": "thresholds"
                }
            }
        ])
    else:
        # Time series uses fixed colors
        override["properties"].append({
            "id": "color",
            "value": {
                "mode": "fixed",
                "fixedColor": sensor["color"]
            }
        })
    
    return override


def create_dashboard(config):
    """Create the complete dashboard structure."""
    sensors = config["sensors"]
    grafana_config = config["grafana"]
    
    dashboard = {
        "id": None,
        "uid": "soil-moisture-main-v2",
        "title": "🌱 Soil Moisture Dashboard",
        "description": "Main dashboard for monitoring soil moisture across all sensors - Mobile optimized",
        "tags": ["overview", "sensors"],
        "style": "dark",
        "timezone": "browser",
        "editable": True,
        "graphTooltip": 1,
        "refresh": "5m",
        "time": {
            "from": "now-7d",
            "to": "now"
        },
        "fiscalYearStartMonth": 0,
        "liveNow": False,
        "schemaVersion": 38,
        "version": 4,
        "templating": {
            "list": [
                {
                    "name": "sensor",
                    "label": "Sensor",
                    "type": "query",
                    "description": "Select sensor to view",
                    "datasource": {
                        "type": "influxdb",
                        "uid": grafana_config["influxdb_datasource_uid"]
                    },
                    "query": {
                        "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: -7d)\n  |> filter(fn: (r) => r._measurement == "{grafana_config["measurement"]}")\n  |> keep(columns: ["device_id"])\n  |> distinct(column: "device_id")\n  |> sort()',
                        "language": "flux"
                    },
                    "refresh": 0,
                    "regex": "",
                    "includeAll": True,
                    "multi": False,
                    "allValue": ".*",
                    "current": {
                        "selected": True,
                        "text": "All",
                        "value": "$__all"
                    },
                    "options": create_dropdown_options(sensors),
                    "skipUrlSync": False,
                    "sort": 1
                }
            ]
        },
        "panels": [
            create_system_status_panel(grafana_config),
            create_rpi_uptime_panel(grafana_config),
            create_last_updated_panel(grafana_config),
            create_current_moisture_panel(sensors, grafana_config),
            create_moisture_trends_panel(sensors, grafana_config),
            create_raw_adc_panel(sensors, grafana_config)
        ]
    }
    
    return dashboard


def create_system_status_panel(grafana_config):
    """Create the System Status stat panel."""
    return {
        "id": 1,
        "type": "stat",
        "title": "System Status",
        "gridPos": {"x": 0, "y": 0, "w": 8, "h": 4},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: -5m)\n  |> filter(fn: (r) => r._measurement == "sensor_heartbeat")\n  |> filter(fn: (r) => r.location != "backyard")\n  |> group(columns: ["device_id"])\n  |> count()\n  |> group()\n  |> count()',
                "refId": "A"
            }
        ],
        "options": {
            "graphMode": "none",
            "colorMode": "background",
            "textMode": "value_and_name",
            "reduceOptions": {
                "values": False,
                "calcs": ["lastNotNull"]
            }
        },
        "fieldConfig": {
            "defaults": {
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "red", "value": None},
                        {"color": "yellow", "value": 1},
                        {"color": "green", "value": 3}
                    ]
                },
                "unit": "short",
                "displayName": "Sensors Online"
            }
        }
    }


def create_rpi_uptime_panel(grafana_config):
    """Create the Raspberry Pi Uptime stat panel."""
    return {
        "id": 998,
        "type": "stat",
        "title": "🖥️ Raspberry Pi Uptime",
        "gridPos": {"x": 8, "y": 0, "w": 8, "h": 4},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: -5m)\n  |> filter(fn: (r) => r._measurement == "rpi_system_metrics")\n  |> filter(fn: (r) => r._field == "uptime_seconds")\n  |> last()',
                "refId": "A"
            }
        ],
        "options": {
            "graphMode": "none",
            "colorMode": "value",
            "textMode": "value",
            "reduceOptions": {
                "values": False,
                "calcs": ["lastNotNull"]
            }
        },
        "fieldConfig": {
            "defaults": {
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "blue", "value": None},
                        {"color": "green", "value": 3600},
                        {"color": "yellow", "value": 86400}
                    ]
                },
                "unit": "s",
                "decimals": 0,
                "displayName": "Server Uptime"
            }
        }
    }


def create_last_updated_panel(grafana_config):
    """Create the Last Updated stat panel."""
    return {
        "id": 999,
        "type": "stat",
        "title": "Last Updated",
        "gridPos": {"x": 16, "y": 0, "w": 8, "h": 4},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: -1h)\n  |> filter(fn: (r) => r._measurement == "{grafana_config["measurement"]}")\n  |> filter(fn: (r) => r.location != "backyard")\n  |> filter(fn: (r) => r._field == "moisture")\n  |> group()\n  |> max(column: "_time")\n  |> map(fn: (r) => ({{_value: int(v: r._time) / int(v: 1000000)}}))',
                "refId": "A"
            }
        ],
        "options": {
            "graphMode": "none",
            "colorMode": "value",
            "textMode": "value",
            "reduceOptions": {
                "values": False,
                "calcs": ["lastNotNull"]
            }
        },
        "fieldConfig": {
            "defaults": {
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [{"color": "green", "value": None}]
                },
                "unit": "dateTimeFromNow",
                "decimals": 0,
                "displayName": "Data Last Received"
            }
        }
    }


def create_current_moisture_panel(sensors, grafana_config):
    """Create the Current Moisture Levels bar gauge panel."""
    return {
        "id": 2,
        "type": "bargauge",
        "title": "Current Moisture Levels",
        "gridPos": {"x": 0, "y": 4, "w": 24, "h": 8},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: -10m)\n  |> filter(fn: (r) => r._measurement == "{grafana_config["measurement"]}")\n  |> filter(fn: (r) => r.location != "backyard")\n  |> filter(fn: (r) => r._field == "moisture")\n  |> filter(fn: (r) => r.device_id =~ /^${{sensor}}$/)\n  |> group(columns: ["device_id"])\n  |> last()\n  |> sort(columns: ["device_id"])',
                "refId": "A"
            }
        ],
        "options": {
            "orientation": "horizontal",
            "displayMode": "gradient",
            "showUnfilled": True,
            "minVizWidth": 0,
            "minVizHeight": 10,
            "reduceOptions": {
                "values": False,
                "calcs": ["lastNotNull"]
            }
        },
        "fieldConfig": {
            "defaults": {
                "unit": "percent",
                "min": 0,
                "max": 100,
                "decimals": 1,
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "dark-green", "value": None},
                        {"color": "semi-dark-green", "value": 50},
                        {"color": "green", "value": 75}
                    ]
                },
                "mappings": [],
                "color": {"mode": "palette-classic"}
            },
            "overrides": [create_field_override(s, is_bargauge=True) for s in sensors]
        }
    }


def create_moisture_trends_panel(sensors, grafana_config):
    """Create the Moisture Trends time series panel."""
    return {
        "id": 3,
        "type": "timeseries",
        "title": "Moisture Trends",
        "gridPos": {"x": 0, "y": 12, "w": 24, "h": 10},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)\n  |> filter(fn: (r) => r._measurement == "{grafana_config["measurement"]}")\n  |> filter(fn: (r) => r._field == "moisture")\n  |> filter(fn: (r) => r.location != "backyard")\n  |> filter(fn: (r) => r.device_id =~ /^${{sensor}}$/)\n  |> aggregateWindow(every: 5m, fn: mean, createEmpty: false)',
                "refId": "A"
            }
        ],
        "options": {
            "tooltip": {"mode": "multi", "sort": "desc"},
            "legend": {
                "displayMode": "table",
                "placement": "bottom",
                "showLegend": True,
                "calcs": ["lastNotNull", "mean", "min", "max"]
            }
        },
        "fieldConfig": {
            "defaults": {
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "lineWidth": 2,
                    "fillOpacity": 10,
                    "gradientMode": "none",
                    "spanNulls": 3600000,
                    "showPoints": "never",
                    "pointSize": 5,
                    "stacking": {"mode": "none", "group": "A"},
                    "axisPlacement": "auto",
                    "axisLabel": "Moisture %",
                    "scaleDistribution": {"type": "linear"}
                },
                "unit": "percent",
                "min": 0,
                "max": 100,
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "transparent", "value": None},
                        {"color": "red", "value": 0},
                        {"color": "yellow", "value": 20},
                        {"color": "green", "value": 40},
                        {"color": "blue", "value": 80}
                    ]
                },
                "color": {"mode": "palette-classic"}
            },
            "overrides": [create_field_override(s) for s in sensors]
        }
    }


def create_raw_adc_panel(sensors, grafana_config):
    """Create the Raw ADC Values time series panel."""
    return {
        "id": 5,
        "type": "timeseries",
        "title": "Raw ADC Values",
        "gridPos": {"x": 0, "y": 22, "w": 24, "h": 10},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)\n  |> filter(fn: (r) => r._measurement == "{grafana_config["measurement"]}")\n  |> filter(fn: (r) => r._field == "raw_adc")\n  |> filter(fn: (r) => r.location != "backyard")\n  |> filter(fn: (r) => r.device_id =~ /^${{sensor}}$/)\n  |> aggregateWindow(every: 5m, fn: mean, createEmpty: false)',
                "refId": "A"
            }
        ],
        "options": {
            "tooltip": {"mode": "multi", "sort": "desc"},
            "legend": {
                "displayMode": "table",
                "placement": "bottom",
                "showLegend": True,
                "calcs": ["lastNotNull", "mean", "min", "max"]
            }
        },
        "fieldConfig": {
            "defaults": {
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "lineWidth": 2,
                    "fillOpacity": 10,
                    "gradientMode": "none",
                    "spanNulls": 3600000,
                    "showPoints": "never",
                    "pointSize": 5,
                    "stacking": {"mode": "none", "group": "A"},
                    "axisPlacement": "auto",
                    "axisLabel": "ADC Value",
                    "scaleDistribution": {"type": "linear"}
                },
                "unit": "short",
                "min": 0,
                "max": 1023,
                "thresholds": {
                    "mode": "absolute",
                    "steps": [{"color": "transparent", "value": None}]
                },
                "color": {"mode": "palette-classic"}
            },
            "overrides": [create_field_override(s) for s in sensors]
        }
    }


def main():
    """Main function to generate the dashboard."""
    import subprocess
    
    # Run validation first
    print("Validating configuration...")
    result = subprocess.run([sys.executable, Path(__file__).parent / "validate-config.py"], 
                          capture_output=True, text=True)
    
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr)
        print("\n✗ Configuration validation failed. Fix errors before generating dashboard.")
        sys.exit(1)
    
    print("✓ Configuration valid\n")
    
    print("Loading sensor configuration...")
    config = load_config()
    
    print(f"Generating dashboard for {len(config['sensors'])} sensors...")
    dashboard = create_dashboard(config)
    
    output_file = Path(__file__).parent / "grafana-dashboards" / "soil-moisture-main.json"
    print(f"Writing dashboard to {output_file}...")
    
    with open(output_file, 'w') as f:
        json.dump(dashboard, f, indent=2)
    
    print("✓ Dashboard generated successfully!")
    print(f"\nSensors configured:")
    for sensor in config['sensors']:
        print(f"  - {sensor['id']}: {sensor['plant']} ({sensor['location']})")
    
    print(f"\nTo upload to Grafana, run:")
    print(f"  ./upload-dashboard-to-pi.sh")


if __name__ == "__main__":
    main()
