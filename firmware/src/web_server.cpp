/*
 * web_server.cpp
 * HTTP server implementation — serves a live dashboard and JSON API
 */

#include "web_server.h"

MonitorWebServer::MonitorWebServer(DataLogger& logger, SoilSensor& sensor,
                                   uint16_t port)
    : _server(port), _logger(logger), _sensor(sensor) {}

void MonitorWebServer::begin() {
    _server.on("/",          HTTP_GET,  [this]() { _handleRoot(); });
    _server.on("/api/latest",   HTTP_GET,  [this]() { _handleLatest(); });
    _server.on("/api/history",  HTTP_GET,  [this]() { _handleHistory(); });
    _server.on("/api/calibrate", HTTP_POST, [this]() { _handleCalibrate(); });
    _server.on("/api/reset",    HTTP_POST, [this]() { _handleReset(); });
    _server.onNotFound([this]() { _handleNotFound(); });

    _server.begin();
    Serial.printf("[HTTP] Server started on port %d\n", HTTP_PORT);
}

void MonitorWebServer::handleClient() {
    _server.handleClient();
}

// ─── Route handlers ──────────────────────────────────────────────────────────

void MonitorWebServer::_handleRoot() {
    _server.send(200, "text/html", _buildDashboardHTML());
}

void MonitorWebServer::_handleLatest() {
    _server.send(200, "application/json", _logger.latestJSON());
}

void MonitorWebServer::_handleHistory() {
    _server.send(200, "application/json", _logger.toJSON());
}

void MonitorWebServer::_handleCalibrate() {
    if (_server.hasArg("air")) {
        _sensor.setAirValue(_server.arg("air").toInt());
    }
    if (_server.hasArg("water")) {
        _sensor.setWaterValue(_server.arg("water").toInt());
    }
    String resp = F("{\"air\":");
    resp += String(_sensor.getAirValue());
    resp += F(",\"water\":");
    resp += String(_sensor.getWaterValue());
    resp += '}';
    _server.send(200, "application/json", resp);
}

void MonitorWebServer::_handleReset() {
    _logger.clear();
    _server.send(200, "application/json", F("{\"status\":\"ok\"}"));
}

void MonitorWebServer::_handleNotFound() {
    _server.send(404, "text/plain", "Not found");
}

// ─── Dashboard HTML ──────────────────────────────────────────────────────────

String MonitorWebServer::_buildDashboardHTML() {
    String html = F(R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Soil Moisture Monitor</title>
<style>
  :root { --bg:#0f172a; --card:#1e293b; --accent:#22d3ee; --text:#e2e8f0; }
  * { box-sizing:border-box; margin:0; padding:0; }
  body { font-family:'Segoe UI',system-ui,sans-serif; background:var(--bg); color:var(--text); display:flex; justify-content:center; padding:1rem; }
  .container { max-width:800px; width:100%; }
  h1 { text-align:center; margin-bottom:1.5rem; color:var(--accent); font-size:1.5rem; }
  .card { background:var(--card); border-radius:12px; padding:1.5rem; margin-bottom:1rem; }
  .value { font-size:3rem; font-weight:700; text-align:center; color:var(--accent); }
  .label { text-align:center; font-size:.9rem; opacity:.7; margin-top:.25rem; }
  .row { display:flex; justify-content:space-between; margin-top:.75rem; }
  .row span { font-size:.85rem; opacity:.8; }
  #status { text-align:center; font-size:.8rem; opacity:.5; margin-top:1rem; }
  #chart { width:100%; height:250px; margin-top:1rem; }
  canvas { border-radius:8px; }
</style>
</head>
<body>
<div class="container">
  <h1>🌱 Soil Moisture Monitor</h1>
  <div class="card">
    <div class="value" id="moisture">--</div>
    <div class="label">Moisture (%)</div>
    <div class="row"><span>Raw ADC:</span><span id="raw">--</span></div>
    <div class="row"><span>Timestamp:</span><span id="ts">--</span></div>
  </div>
  <div class="card">
    <canvas id="chart"></canvas>
    <div style="text-align:center;margin-top:0.5rem;font-size:0.85rem;opacity:0.7;">24-Hour History</div>
  </div>
  <div class="card">
    <div class="row"><span>Readings logged:</span><span id="count">--</span></div>
    <div class="row"><span>IP address:</span><span>)rawliteral");

    html += WiFi.localIP().toString();

    html += F(R"rawliteral(</span></div>
  </div>
  <div id="status">Updating every 5 s</div>
</div>
<script>
let chart;
async function refresh(){
  try{
    const r=await fetch('/api/latest');
    const d=await r.json();
    document.getElementById('moisture').textContent=d.moisture.toFixed(1)+'%';
    document.getElementById('raw').textContent=d.raw;
    document.getElementById('ts').textContent=new Date(d.ts*1000).toLocaleString();
    const h=await fetch('/api/history');
    const hd=await h.json();
    document.getElementById('count').textContent=hd.count;
    drawChart(hd.readings);
  }catch(e){ console.error(e); }
}
function drawChart(data){
  const canvas=document.getElementById('chart');
  const ctx=canvas.getContext('2d');
  const w=canvas.width=canvas.offsetWidth*2;
  const h=canvas.height=500;
  ctx.clearRect(0,0,w,h);
  if(!data||data.length<2)return;
  const maxPoints=Math.min(data.length,288);
  const step=Math.max(1,Math.floor(data.length/maxPoints));
  const points=[];
  for(let i=0;i<data.length;i+=step){
    points.push(data[i]);
  }
  const pad=60;
  const cw=w-pad*2;
  const ch=h-pad*2;
  ctx.strokeStyle='#334155';
  ctx.lineWidth=2;
  for(let i=0;i<=5;i++){
    const y=pad+ch-(i/5)*ch;
    ctx.beginPath();
    ctx.moveTo(pad,y);
    ctx.lineTo(w-pad,y);
    ctx.stroke();
    ctx.fillStyle='#64748b';
    ctx.font='24px sans-serif';
    ctx.textAlign='right';
    ctx.fillText((i*20)+'%',pad-10,y+8);
  }
  ctx.strokeStyle='#22d3ee';
  ctx.lineWidth=4;
  ctx.beginPath();
  points.forEach((p,i)=>{
    const x=pad+(i/(points.length-1))*cw;
    const y=pad+ch-(p.moisture/100)*ch;
    if(i===0)ctx.moveTo(x,y);
    else ctx.lineTo(x,y);
  });
  ctx.stroke();
  ctx.fillStyle='#22d3ee';
  points.forEach((p,i)=>{
    const x=pad+(i/(points.length-1))*cw;
    const y=pad+ch-(p.moisture/100)*ch;
    ctx.beginPath();
    ctx.arc(x,y,6,0,Math.PI*2);
    ctx.fill();
  });
}
refresh();
setInterval(refresh,5000);
</script>
</body>
</html>
)rawliteral");

    return html;
}
