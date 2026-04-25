#!/usr/bin/env python3
"""
Simple database server for soil moisture monitoring system
Receives readings from ESP8266 via HTTP POST and stores in SQLite
"""

from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS
import sqlite3
import time
from datetime import datetime
import os

app = Flask(__name__)
CORS(app)  # Enable CORS for web dashboard access

DB_PATH = os.path.join(os.path.dirname(__file__), 'sensor_data.db')

# ─── Database initialization ──────────────────────────────────────────────────

def init_db():
    """Initialize SQLite database with schema for multi-sensor support"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Devices table - track each sensor
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS devices (
            device_id TEXT PRIMARY KEY,
            name TEXT,
            location TEXT,
            mac_address TEXT,
            first_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            total_readings INTEGER DEFAULT 0
        )
    ''')
    
    # Readings table - now with device_id foreign key
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS readings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            raw INTEGER NOT NULL,
            moisture REAL NOT NULL,
            uptime INTEGER,
            crashes INTEGER DEFAULT 0,
            received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (device_id) REFERENCES devices(device_id)
        )
    ''')
    
    # Indexes for performance
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_timestamp ON readings(timestamp)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_received_at ON readings(received_at)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_device_id ON readings(device_id)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_device_timestamp ON readings(device_id, timestamp)')
    
    conn.commit()
    conn.close()
    print(f"✓ Database initialized: {DB_PATH}")

# ─── API Endpoints ────────────────────────────────────────────────────────────

@app.route('/api/reading', methods=['POST'])
def add_reading():
    """Receive a new sensor reading from ESP8266"""
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'No JSON data received'}), 400
        
        # Extract fields
        device_id = data.get('device_id')
        timestamp = data.get('timestamp', int(time.time()))
        raw = data.get('raw')
        moisture = data.get('moisture')
        uptime = data.get('uptime', 0)
        crashes = data.get('crashes', 0)
        
        # Device ID is required
        if not device_id:
            return jsonify({'error': 'Missing device_id'}), 400
            
        if raw is None or moisture is None:
            return jsonify({'error': 'Missing required fields: raw, moisture'}), 400
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Register or update device
        cursor.execute('''
            INSERT INTO devices (device_id, last_seen, total_readings)
            VALUES (?, CURRENT_TIMESTAMP, 1)
            ON CONFLICT(device_id) DO UPDATE SET
                last_seen = CURRENT_TIMESTAMP,
                total_readings = total_readings + 1
        ''')
        
        # Store reading
        cursor.execute('''
            INSERT INTO readings (device_id, timestamp, raw, moisture, uptime, crashes)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (device_id, timestamp, raw, moisture, uptime, crashes))
        
        reading_id = cursor.lastrowid
        conn.commit()
        conn.close()
        
        print(f"✓ [{device_id}] Reading #{reading_id}: {moisture:.1f}% (raw={raw})")
        
        return jsonify({
            'id': reading_id,
            'status': 'ok',
            'timestamp': timestamp
        }), 201
        
    except Exception as e:
        print(f"✗ Error storing reading: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/latest', methods=['GET'])
def get_latest():
    """Get the most recent sensor reading (optionally filtered by device_id)"""
    try:
        device_id = request.args.get('device_id')
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        if device_id:
            cursor.execute('''
                SELECT device_id, timestamp, raw, moisture, uptime, crashes, received_at
                FROM readings
                WHERE device_id = ?
                ORDER BY id DESC
                LIMIT 1
            ''', (device_id,))
        else:
            # Return latest from ALL devices
            cursor.execute('''
                SELECT device_id, timestamp, raw, moisture, uptime, crashes, received_at
                FROM readings
                ORDER BY id DESC
                LIMIT 1
            ''')
        
        row = cursor.fetchone()
        conn.close()
        
        if not row:
            return jsonify({'error': 'No readings available'}), 404
        
        return jsonify({
            'device_id': row[0],
            'ts': row[1],
            'raw': row[2],
            'moisture': row[3],
            'uptime': row[4],
            'crashes': row[5],
            'received_at': row[6]
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/history', methods=['GET'])
def get_history():
    """Get historical readings (optionally filtered by device_id)"""
    try:
        # Query parameters
        device_id = request.args.get('device_id')
        limit = request.args.get('limit', 288, type=int)  # Default: 24h at 5min intervals
        offset = request.args.get('offset', 0, type=int)
        
        # Limit maximum to prevent overload
        if limit > 10000:
            limit = 10000
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        if device_id:
            cursor.execute('''
                SELECT device_id, timestamp, raw, moisture, uptime, crashes
                FROM readings
                WHERE device_id = ?
                ORDER BY id DESC
                LIMIT ? OFFSET ?
            ''', (device_id, limit, offset))
            
            cursor.execute('SELECT COUNT(*) FROM readings WHERE device_id = ?', (device_id,))
        else:
            cursor.execute('''
                SELECT device_id, timestamp, raw, moisture, uptime, crashes
                FROM readings
                ORDER BY id DESC
                LIMIT ? OFFSET ?
            ''', (limit, offset))
            
            cursor.execute('SELECT COUNT(*) FROM readings')
        
        rows = cursor.fetchall()
        total_count = cursor.fetchone()[0]
        conn.close()
        
        readings = []
        for row in rows:
            readings.append({
                'device_id': row[0],
                'ts': row[1],
                'raw': row[2],
                'moisture': row[3],
                'uptime': row[4],
                'crashes': row[5]
            })
        
        # Reverse so oldest is first
        readings.reverse()
        
        return jsonify({
            'count': len(readings),
            'total': total_count,
            'readings': readings
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/devices', methods=['GET'])
def get_devices():
    """Get list of all registered devices"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT device_id, name, location, mac_address, first_seen, last_seen, total_readings
            FROM devices
            ORDER BY last_seen DESC
        ''')
        
        rows = cursor.fetchall()
        conn.close()
        
        devices = []
        for row in rows:
            devices.append({
                'device_id': row[0],
                'name': row[1],
                'location': row[2],
                'mac_address': row[3],
                'first_seen': row[4],
                'last_seen': row[5],
                'total_readings': row[6]
            })
        
        return jsonify({
            'count': len(devices),
            'devices': devices
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/devices/<device_id>', methods=['GET'])
def get_device(device_id):
    """Get information about a specific device"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT device_id, name, location, mac_address, first_seen, last_seen, total_readings
            FROM devices
            WHERE device_id = ?
        ''', (device_id,))
        
        row = cursor.fetchone()
        
        if not row:
            conn.close()
            return jsonify({'error': 'Device not found'}), 404
        
        # Get latest reading
        cursor.execute('''
            SELECT timestamp, moisture, raw
            FROM readings
            WHERE device_id = ?
            ORDER BY id DESC
            LIMIT 1
        ''', (device_id,))
        
        latest = cursor.fetchone()
        conn.close()
        
        device_info = {
            'device_id': row[0],
            'name': row[1],
            'location': row[2],
            'mac_address': row[3],
            'first_seen': row[4],
            'last_seen': row[5],
            'total_readings': row[6]
        }
        
        if latest:
            device_info['latest_reading'] = {
                'timestamp': latest[0],
                'moisture': latest[1],
                'raw': latest[2]
            }
        
        return jsonify(device_info)
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/devices/<device_id>', methods=['PUT'])
def update_device(device_id):
    """Update device metadata (name, location)"""
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'No JSON data received'}), 400
        
        name = data.get('name')
        location = data.get('location')
        mac_address = data.get('mac_address')
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Check if device exists
        cursor.execute('SELECT device_id FROM devices WHERE device_id = ?', (device_id,))
        if not cursor.fetchone():
            conn.close()
            return jsonify({'error': 'Device not found'}), 404
        
        # Build update query dynamically
        updates = []
        params = []
        
        if name is not None:
            updates.append('name = ?')
            params.append(name)
        if location is not None:
            updates.append('location = ?')
            params.append(location)
        if mac_address is not None:
            updates.append('mac_address = ?')
            params.append(mac_address)
        
        if not updates:
            conn.close()
            return jsonify({'error': 'No fields to update'}), 400
        
        params.append(device_id)
        query = f"UPDATE devices SET {', '.join(updates)} WHERE device_id = ?"
        
        cursor.execute(query, params)
        conn.commit()
        conn.close()
        
        return jsonify({'status': 'ok', 'device_id': device_id})
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/devices/all/latest', methods=['GET'])
def get_all_latest():
    """Get the latest reading from each device"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Get latest reading for each device
        cursor.execute('''
            SELECT r.device_id, d.name, d.location, r.timestamp, r.moisture, r.raw, r.uptime, r.crashes
            FROM readings r
            INNER JOIN (
                SELECT device_id, MAX(id) as max_id
                FROM readings
                GROUP BY device_id
            ) latest ON r.id = latest.max_id
            LEFT JOIN devices d ON r.device_id = d.device_id
            ORDER BY r.timestamp DESC
        ''')
        
        rows = cursor.fetchall()
        conn.close()
        
        devices = []
        for row in rows:
            devices.append({
                'device_id': row[0],
                'name': row[1],
                'location': row[2],
                'timestamp': row[3],
                'moisture': row[4],
                'raw': row[5],
                'uptime': row[6],
                'crashes': row[7]
            })
        
        return jsonify({
            'count': len(devices),
            'devices': devices
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/stats', methods=['GET'])
def get_stats():
    """Get statistics about the database (optionally filtered by device_id)"""
    try:
        device_id = request.args.get('device_id')
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        if device_id:
            # Stats for specific device
            cursor.execute('SELECT COUNT(*) FROM readings WHERE device_id = ?', (device_id,))
            total = cursor.fetchone()[0]
            
            cursor.execute('SELECT MIN(timestamp), MAX(timestamp) FROM readings WHERE device_id = ?', (device_id,))
            first_ts, last_ts = cursor.fetchone()
            
            cursor.execute('SELECT AVG(moisture) FROM readings WHERE device_id = ?', (device_id,))
            avg_moisture = cursor.fetchone()[0]
            
            cursor.execute('SELECT MAX(crashes) FROM readings WHERE device_id = ?', (device_id,))
            max_crashes = cursor.fetchone()[0] or 0
            
            stats = {
                'device_id': device_id,
                'total_readings': total,
                'first_reading': first_ts,
                'last_reading': last_ts,
                'avg_moisture': round(avg_moisture, 1) if avg_moisture else 0,
                'max_crashes': max_crashes
            }
        else:
            # Overall stats
            cursor.execute('SELECT COUNT(*) FROM readings')
            total = cursor.fetchone()[0]
            
            cursor.execute('SELECT COUNT(*) FROM devices')
            device_count = cursor.fetchone()[0]
            
            cursor.execute('SELECT MIN(timestamp), MAX(timestamp) FROM readings')
            first_ts, last_ts = cursor.fetchone()
            
            cursor.execute('SELECT AVG(moisture) FROM readings')
            avg_moisture = cursor.fetchone()[0]
            
            stats = {
                'total_devices': device_count,
                'total_readings': total,
                'first_reading': first_ts,
                'last_reading': last_ts,
                'avg_moisture': round(avg_moisture, 1) if avg_moisture else 0
            }
        
        conn.close()
        return jsonify(stats)
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/reset', methods=['POST'])
def reset_database():
    """Clear all readings (use with caution!)"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('DELETE FROM readings')
        conn.commit()
        conn.close()
        
        print("⚠️  Database cleared")
        return jsonify({'status': 'ok', 'message': 'All readings deleted'})
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'database': DB_PATH,
        'timestamp': int(time.time())
    })

@app.route('/', methods=['GET'])
def index():
    """Simple status page"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        cursor.execute('SELECT COUNT(*) FROM readings')
        reading_count = cursor.fetchone()[0]
        
        cursor.execute('SELECT COUNT(*) FROM devices')
        device_count = cursor.fetchone()[0]
        
        conn.close()
        
        return f"""
        <html>
        <head><title>Soil Sensor Database</title></head>
        <body style="font-family: monospace; padding: 2rem; background: #0f172a; color: #e2e8f0;">
            <h1>🌱 Soil Moisture Database Server</h1>
            <p>Status: <strong style="color: #22d3ee;">Running</strong></p>
            <p>Devices: <strong>{device_count}</strong></p>
            <p>Readings stored: <strong>{reading_count}</strong></p>
            <hr style="border-color: #334155;">
            <h2>API Endpoints:</h2>
            <h3>Readings:</h3>
            <ul>
                <li><code>POST /api/reading</code> - Store new reading (requires device_id)</li>
                <li><code>GET /api/latest?device_id=xxx</code> - Get latest reading</li>
                <li><code>GET /api/history?device_id=xxx&limit=288</code> - Get history</li>
                <li><code>GET /api/stats?device_id=xxx</code> - Get statistics</li>
            </ul>
            <h3>Devices:</h3>
            <ul>
                <li><code>GET /api/devices</code> - List all devices</li>
                <li><code>GET /api/devices/&lt;id&gt;</code> - Get device info</li>
                <li><code>PUT /api/devices/&lt;id&gt;</code> - Update device (name, location)</li>
                <li><code>GET /api/devices/all/latest</code> - Latest reading from each device</li>
            </ul>
            <h3>System:</h3>
            <ul>
                <li><code>GET /health</code> - Health check</li>
                <li><code>POST /api/reset</code> - Clear all data</li>
            </ul>
            <hr style="border-color: #334155;">
            <p><a href="/dashboard" style="color: #22d3ee;">View Dashboard →</a></p>
        </body>
        </html>
        """
    except Exception as e:
        return f"<h1>Database Error</h1><p>{e}</p>", 500

# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    print("═══════════════════════════════════════")
    print("  🌱 Soil Moisture Database Server")
    print("═══════════════════════════════════════")
    
    # Initialize database
    init_db()
    
    print("\nStarting Flask server...")
    print("Server will be available at:")
    print("  - http://localhost:5001")
    print("  - http://192.168.99.188:5001 (if on same network)")
    print("\nPress Ctrl+C to stop\n")
    
    # Run server
    app.run(host='0.0.0.0', port=5001, debug=False)
