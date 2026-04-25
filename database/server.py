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
    """Initialize SQLite database with schema"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS readings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            raw INTEGER NOT NULL,
            moisture REAL NOT NULL,
            uptime INTEGER,
            crashes INTEGER DEFAULT 0,
            received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_timestamp ON readings(timestamp)
    ''')
    
    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_received_at ON readings(received_at)
    ''')
    
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
        timestamp = data.get('timestamp', int(time.time()))
        raw = data.get('raw')
        moisture = data.get('moisture')
        uptime = data.get('uptime', 0)
        crashes = data.get('crashes', 0)
        
        if raw is None or moisture is None:
            return jsonify({'error': 'Missing required fields: raw, moisture'}), 400
        
        # Store in database
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO readings (timestamp, raw, moisture, uptime, crashes)
            VALUES (?, ?, ?, ?, ?)
        ''', (timestamp, raw, moisture, uptime, crashes))
        
        reading_id = cursor.lastrowid
        conn.commit()
        conn.close()
        
        print(f"✓ Reading #{reading_id}: {moisture:.1f}% (raw={raw}, uptime={uptime}s, crashes={crashes})")
        
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
    """Get the most recent sensor reading"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT timestamp, raw, moisture, uptime, crashes, received_at
            FROM readings
            ORDER BY id DESC
            LIMIT 1
        ''')
        
        row = cursor.fetchone()
        conn.close()
        
        if not row:
            return jsonify({'error': 'No readings available'}), 404
        
        return jsonify({
            'ts': row[0],
            'raw': row[1],
            'moisture': row[2],
            'uptime': row[3],
            'crashes': row[4],
            'received_at': row[5]
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/history', methods=['GET'])
def get_history():
    """Get historical readings"""
    try:
        # Query parameters
        limit = request.args.get('limit', 288, type=int)  # Default: 24h at 5min intervals
        offset = request.args.get('offset', 0, type=int)
        
        # Limit maximum to prevent overload
        if limit > 10000:
            limit = 10000
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT timestamp, raw, moisture, uptime, crashes
            FROM readings
            ORDER BY id DESC
            LIMIT ? OFFSET ?
        ''', (limit, offset))
        
        rows = cursor.fetchall()
        
        # Get total count
        cursor.execute('SELECT COUNT(*) FROM readings')
        total_count = cursor.fetchone()[0]
        
        conn.close()
        
        readings = []
        for row in rows:
            readings.append({
                'ts': row[0],
                'raw': row[1],
                'moisture': row[2],
                'uptime': row[3],
                'crashes': row[4]
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

@app.route('/api/stats', methods=['GET'])
def get_stats():
    """Get statistics about the database"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Total readings
        cursor.execute('SELECT COUNT(*) FROM readings')
        total = cursor.fetchone()[0]
        
        # First and last reading times
        cursor.execute('SELECT MIN(timestamp), MAX(timestamp) FROM readings')
        first_ts, last_ts = cursor.fetchone()
        
        # Average moisture
        cursor.execute('SELECT AVG(moisture) FROM readings')
        avg_moisture = cursor.fetchone()[0]
        
        # Max crashes reported
        cursor.execute('SELECT MAX(crashes) FROM readings')
        max_crashes = cursor.fetchone()[0] or 0
        
        conn.close()
        
        return jsonify({
            'total_readings': total,
            'first_reading': first_ts,
            'last_reading': last_ts,
            'avg_moisture': round(avg_moisture, 1) if avg_moisture else 0,
            'max_crashes': max_crashes
        })
        
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
        count = cursor.fetchone()[0]
        conn.close()
        
        return f"""
        <html>
        <head><title>Soil Sensor Database</title></head>
        <body style="font-family: monospace; padding: 2rem; background: #0f172a; color: #e2e8f0;">
            <h1>🌱 Soil Moisture Database Server</h1>
            <p>Status: <strong style="color: #22d3ee;">Running</strong></p>
            <p>Readings stored: <strong>{count}</strong></p>
            <hr style="border-color: #334155;">
            <h2>API Endpoints:</h2>
            <ul>
                <li><code>POST /api/reading</code> - Store new reading</li>
                <li><code>GET /api/latest</code> - Get latest reading</li>
                <li><code>GET /api/history?limit=288</code> - Get history</li>
                <li><code>GET /api/stats</code> - Get statistics</li>
                <li><code>GET /health</code> - Health check</li>
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
