#!/usr/bin/env python3
"""
Generate Grafana dashboards from centralized sensor configuration.

This script reads sensors-config.json and generates two dashboards with all
sensor configurations, labels, colors, and filters:

  * soil-moisture-main.json — the main dashboard. No template variables: the
    status bar, one full-width trace panel per plant, and the ambient climate
    panels.
  * sensor-explorer.json — the Sensor dropdown and every panel that filters on
    it (plant heading, current levels, overlaid moisture trends, raw ADC).

Usage:
    ./generate-dashboard.py

Output:
    grafana-dashboards/soil-moisture-main.json
    grafana-dashboards/sensor-explorer.json
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
    """Create the main dashboard: status bar, per-plant traces, ambient climate.

    This dashboard deliberately has no template variables. Every panel that
    filtered on the Sensor dropdown lives on the sensor explorer dashboard
    (see create_sensor_explorer_dashboard), so what is left here always shows
    one trace per plant with nothing to select first.
    """
    sensors = config["sensors"]
    grafana_config = config["grafana"]
    climate_sensors = config.get("climate_sensors", [])

    status_y = 0
    status_height = 4

    # One full-width single-trace moisture panel per plant, in sensor order.
    per_plant_start_y = status_y + status_height
    per_plant_height = 8
    per_plant_panels = [
        create_single_plant_moisture_panel(
            sensor,
            panel_id=101 + index,
            y_pos=per_plant_start_y + index * per_plant_height,
            height=per_plant_height,
            grafana_config=grafana_config
        )
        for index, sensor in enumerate(sensors)
    ]

    # Ambient climate sits below the plant traces.
    climate_stats_y = per_plant_start_y + len(sensors) * per_plant_height
    temperature_trend_y = climate_stats_y + 6
    humidity_trend_y = temperature_trend_y + 10

    return {
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
        "version": 5,
        "templating": {
            "list": []
        },
        "panels": [
            create_system_status_panel(sensors, climate_sensors, grafana_config, status_y),
            create_rpi_uptime_panel(grafana_config, status_y),
            create_last_updated_panel(grafana_config, status_y),
            *per_plant_panels,
            create_temperature_stat_panel(climate_sensors, grafana_config, climate_stats_y),
            create_humidity_stat_panel(climate_sensors, grafana_config, climate_stats_y),
            create_temperature_trends_panel(climate_sensors, grafana_config, temperature_trend_y),
            create_humidity_trends_panel(climate_sensors, grafana_config, humidity_trend_y)
        ]
    }


def create_sensor_explorer_dashboard(config):
    """Create the sensor explorer dashboard: the Sensor dropdown and its panels.

    These panels all filter on ${sensor}, so they only make sense next to the
    selector. They used to live on the main dashboard above the per-plant
    traces.
    """
    sensors = config["sensors"]
    grafana_config = config["grafana"]

    plant_name_y = 0
    current_moisture_y = plant_name_y + 3
    moisture_trends_y = current_moisture_y + 8
    raw_adc_y = moisture_trends_y + 10

    return {
        "id": None,
        "uid": "sensor-explorer-v1",
        "title": "🔍 Sensor Explorer",
        "description": "Pick a plant (or All) from the Sensor dropdown to compare current levels, moisture trends, and raw ADC values",
        "tags": ["overview", "sensors", "explorer"],
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
        "version": 1,
        "templating": {
            "list": [
                {
                    "name": "sensor",
                    "label": "Sensor",
                    "type": "custom",
                    "description": "Select sensor to view",
                    "query": ", ".join(f'{s["plant"]} : {s["id"]}' for s in sensors),
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
            create_plant_name_panel(sensors, grafana_config, plant_name_y),
            create_current_moisture_panel(sensors, grafana_config, current_moisture_y),
            create_moisture_trends_panel(sensors, grafana_config, moisture_trends_y),
            create_raw_adc_panel(sensors, grafana_config, raw_adc_y)
        ]
    }


def create_plant_name_panel(sensors, grafana_config, y_pos):
    """Create the plant name heading panel with dynamic color matching."""
    # Build the Flux if/else chain for sensor-to-plant mapping
    flux_conditions = []
    for sensor in sensors:
        flux_conditions.append(f'  else if sensor == "{sensor["id"]}" then [{{_time: now(), _value: "{sensor["plant"]}", _field: "plant_name"}}]')
    
    flux_query = f'''import "array"
import "experimental"

sensor = "${{sensor}}"

data = if sensor == ".*" then [{{_time: now(), _value: "All Plants", _field: "plant_name"}}]
{chr(10).join(flux_conditions)}
  else [{{_time: now(), _value: "All Plants", _field: "plant_name"}}]

array.from(rows: data)'''
    
    # Build value mappings for colors
    mappings = [
        {
            "type": "value",
            "options": {
                "All Plants": {
                    "color": "#5794F2",
                    "index": 0
                }
            }
        }
    ]
    
    for i, sensor in enumerate(sensors):
        mappings.append({
            "type": "value",
            "options": {
                sensor["plant"]: {
                    "color": sensor["color"],
                    "index": i + 1
                }
            }
        })
    
    return {
        "id": 1001,
        "type": "stat",
        "title": "",
        "gridPos": {"x": 0, "y": y_pos, "w": 24, "h": 3},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": flux_query,
                "refId": "A"
            }
        ],
        "options": {
            "graphMode": "none",
            "colorMode": "background",
            "textMode": "value",
            "reduceOptions": {
                "values": True,
                "fields": "/_value/",
                "calcs": ["lastNotNull"]
            },
            "text": {
                "titleSize": 16,
                "valueSize": 48
            }
        },
        "transparent": False,
        "fieldConfig": {
            "defaults": {
                "mappings": mappings,
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "blue", "value": None}
                    ]
                }
            },
            "overrides": []
        }
    }


def create_system_status_panel(sensors, climate_sensors, grafana_config, y_pos):
    """Create the System Status stat panel.

    Counts all sensors defined in sensors-config.json (soil + climate) by
    device_id, so unknown devices don't inflate the count.
    """
    all_ids = [s["id"] for s in sensors] + [s["id"] for s in climate_sensors]
    total = len(all_ids)
    id_regex = "^(" + "|".join(all_ids) + ")$"
    return {
        "id": 1,
        "type": "stat",
        "title": "System Status",
        "gridPos": {"x": 0, "y": y_pos, "w": 8, "h": 4},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: -10m)\n  |> filter(fn: (r) => r._measurement == "sensor_heartbeat")\n  |> filter(fn: (r) => r.device_id =~ /{id_regex}/)\n  |> group(columns: ["device_id"])\n  |> count()\n  |> group()\n  |> count()',
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
                        {"color": "green", "value": total}
                    ]
                },
                "unit": "short",
                "displayName": f"Sensors Online (of {total})"
            }
        }
    }


def create_rpi_uptime_panel(grafana_config, y_pos):
    """Create the Raspberry Pi Uptime stat panel."""
    return {
        "id": 998,
        "type": "stat",
        "title": "🖥️ Raspberry Pi Uptime",
        "gridPos": {"x": 8, "y": y_pos, "w": 8, "h": 4},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: -1h)\n  |> filter(fn: (r) => r._measurement == "rpi_system_metrics")\n  |> filter(fn: (r) => r._field == "uptime_seconds")\n  |> last()',
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


def create_last_updated_panel(grafana_config, y_pos):
    """Create the Last Updated stat panel."""
    return {
        "id": 999,
        "type": "stat",
        "title": "Last Updated",
        "gridPos": {"x": 16, "y": y_pos, "w": 8, "h": 4},
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


def create_current_moisture_panel(sensors, grafana_config, y_pos):
    """Create the Current Moisture Levels bar gauge panel."""
    return {
        "id": 2,
        "type": "bargauge",
        "title": "Current Moisture Levels",
        "gridPos": {"x": 0, "y": y_pos, "w": 24, "h": 8},
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


def create_moisture_trends_panel(sensors, grafana_config, y_pos):
    """Create the Moisture Trends time series panel."""
    return {
        "id": 3,
        "type": "timeseries",
        "title": "Moisture Trends",
        "gridPos": {"x": 0, "y": y_pos, "w": 24, "h": 10},
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


def create_single_plant_moisture_panel(sensor, panel_id, y_pos, height, grafana_config):
    """Create a single-trace moisture time series panel for one plant.

    Unlike the overlay "Moisture Trends" panel, this always shows exactly one
    plant (independent of the dropdown selection), full width, so a single
    trace is easy to read. The plant's fancy name is used for the panel title
    and the series display name / legend / tooltip.
    """
    plant_name = sensor["plant"]
    return {
        "id": panel_id,
        "type": "timeseries",
        "title": plant_name,
        "gridPos": {"x": 0, "y": y_pos, "w": 24, "h": height},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)\n  |> filter(fn: (r) => r._measurement == "{grafana_config["measurement"]}")\n  |> filter(fn: (r) => r._field == "moisture")\n  |> filter(fn: (r) => r.device_id == "{sensor["id"]}")\n  |> aggregateWindow(every: 5m, fn: mean, createEmpty: false)',
                "refId": "A"
            }
        ],
        "options": {
            "tooltip": {"mode": "single", "sort": "none"},
            "legend": {
                "displayMode": "table",
                "placement": "bottom",
                "showLegend": True,
                "calcs": ["lastNotNull", "mean", "min", "max"]
            }
        },
        "fieldConfig": {
            "defaults": {
                "displayName": plant_name,
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
                    "steps": [{"color": "transparent", "value": None}]
                },
                "color": {"mode": "fixed", "fixedColor": sensor["color"]}
            },
            "overrides": []
        }
    }


def create_raw_adc_panel(sensors, grafana_config, y_pos):
    """Create the Raw ADC Values time series panel."""
    return {
        "id": 5,
        "type": "timeseries",
        "title": "Raw ADC Values",
        "gridPos": {"x": 0, "y": y_pos, "w": 24, "h": 10},
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


def create_climate_field_override(sensor):
    """Field override (display name + fixed color) for a climate sensor."""
    return {
        "matcher": {
            "id": "byRegexp",
            "options": f".*{sensor['id']}.*"
        },
        "properties": [
            {"id": "displayName", "value": sensor["label"]},
            {"id": "color", "value": {"mode": "fixed", "fixedColor": sensor["color"]}}
        ]
    }


def _climate_measurement(grafana_config):
    return grafana_config.get("climate_measurement", "climate_reading")


def create_temperature_stat_panel(climate_sensors, grafana_config, y_pos):
    """Current ambient temperature as a single number with °F unit."""
    measurement = _climate_measurement(grafana_config)
    return {
        "id": 20,
        "type": "stat",
        "title": "Ambient Temperature",
        "gridPos": {"x": 0, "y": y_pos, "w": 12, "h": 6},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: -30m)\n  |> filter(fn: (r) => r._measurement == "{measurement}")\n  |> filter(fn: (r) => r._field == "temperature_f")\n  |> group(columns: ["device_id"])\n  |> last()',
                "refId": "A"
            }
        ],
        "options": {
            "graphMode": "none",
            "colorMode": "value",
            "textMode": "value",
            "justifyMode": "auto",
            "reduceOptions": {
                "values": False,
                "calcs": ["lastNotNull"]
            }
        },
        "fieldConfig": {
            "defaults": {
                "unit": "fahrenheit",
                "decimals": 1,
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "blue", "value": None},
                        {"color": "green", "value": 60},
                        {"color": "orange", "value": 80},
                        {"color": "red", "value": 90}
                    ]
                }
            },
            "overrides": [create_climate_field_override(s) for s in climate_sensors]
        }
    }


def create_humidity_stat_panel(climate_sensors, grafana_config, y_pos):
    """Current ambient humidity as a single number with % unit."""
    measurement = _climate_measurement(grafana_config)
    return {
        "id": 21,
        "type": "stat",
        "title": "Ambient Humidity",
        "gridPos": {"x": 12, "y": y_pos, "w": 12, "h": 6},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: -30m)\n  |> filter(fn: (r) => r._measurement == "{measurement}")\n  |> filter(fn: (r) => r._field == "humidity")\n  |> group(columns: ["device_id"])\n  |> last()',
                "refId": "A"
            }
        ],
        "options": {
            "graphMode": "none",
            "colorMode": "value",
            "textMode": "value",
            "justifyMode": "auto",
            "reduceOptions": {
                "values": False,
                "calcs": ["lastNotNull"]
            }
        },
        "fieldConfig": {
            "defaults": {
                "unit": "humidity",
                "decimals": 1,
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "red", "value": None},
                        {"color": "orange", "value": 30},
                        {"color": "green", "value": 40},
                        {"color": "blue", "value": 60}
                    ]
                }
            },
            "overrides": [create_climate_field_override(s) for s in climate_sensors]
        }
    }


def create_temperature_trends_panel(climate_sensors, grafana_config, y_pos):
    """Ambient temperature (°F) time series."""
    measurement = _climate_measurement(grafana_config)
    return {
        "id": 22,
        "type": "timeseries",
        "title": "Ambient Temperature Trend (°F)",
        "gridPos": {"x": 0, "y": y_pos, "w": 24, "h": 10},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)\n  |> filter(fn: (r) => r._measurement == "{measurement}")\n  |> filter(fn: (r) => r._field == "temperature_f")\n  |> aggregateWindow(every: 5m, fn: mean, createEmpty: false)',
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
                    "axisLabel": "Temperature °F",
                    "scaleDistribution": {"type": "linear"}
                },
                "unit": "fahrenheit",
                "thresholds": {
                    "mode": "absolute",
                    "steps": [{"color": "transparent", "value": None}]
                },
                "color": {"mode": "palette-classic"}
            },
            "overrides": [create_climate_field_override(s) for s in climate_sensors]
        }
    }


def create_humidity_trends_panel(climate_sensors, grafana_config, y_pos):
    """Ambient humidity (%) time series."""
    measurement = _climate_measurement(grafana_config)
    return {
        "id": 23,
        "type": "timeseries",
        "title": "Ambient Humidity Trend (%)",
        "gridPos": {"x": 0, "y": y_pos, "w": 24, "h": 10},
        "datasource": {
            "type": "influxdb",
            "uid": grafana_config["influxdb_datasource_uid"]
        },
        "targets": [
            {
                "query": f'from(bucket: "{grafana_config["bucket"]}")\n  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)\n  |> filter(fn: (r) => r._measurement == "{measurement}")\n  |> filter(fn: (r) => r._field == "humidity")\n  |> aggregateWindow(every: 5m, fn: mean, createEmpty: false)',
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
                    "axisLabel": "Humidity %",
                    "scaleDistribution": {"type": "linear"}
                },
                "unit": "humidity",
                "min": 0,
                "max": 100,
                "thresholds": {
                    "mode": "absolute",
                    "steps": [{"color": "transparent", "value": None}]
                },
                "color": {"mode": "palette-classic"}
            },
            "overrides": [create_climate_field_override(s) for s in climate_sensors]
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
    
    print(f"Generating dashboards for {len(config['sensors'])} sensors...")

    # Write to the repo-root grafana-dashboards/ (the directory
    # upload-dashboard-to-pi.sh and import-all-dashboards.sh deploy from)
    dashboard_dir = Path(__file__).parent.parent / "grafana-dashboards"
    outputs = [
        ("soil-moisture-main.json", create_dashboard(config)),
        ("sensor-explorer.json", create_sensor_explorer_dashboard(config)),
    ]

    for filename, dashboard in outputs:
        output_file = dashboard_dir / filename
        print(f"Writing dashboard to {output_file}...")
        with open(output_file, 'w') as f:
            json.dump(dashboard, f, indent=2)

    print("✓ Dashboards generated successfully!")
    print(f"\nSensors configured:")
    for sensor in config['sensors']:
        print(f"  - {sensor['id']}: {sensor['plant']} ({sensor['location']})")
    
    print(f"\nTo upload the main dashboard to Grafana, run:")
    print(f"  ./upload-dashboard-to-pi.sh")
    print(f"To upload every dashboard, run:")
    print(f"  ../grafana-dashboards/import-all-dashboards.sh")


if __name__ == "__main__":
    main()
