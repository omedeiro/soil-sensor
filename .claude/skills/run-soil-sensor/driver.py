#!/usr/bin/env python3
"""
driver.py — run and drive the soil-sensor system on a dev machine.

There is no single "app" to launch here: the product is ESP8266 firmware +
InfluxDB + Grafana on a Raspberry Pi. What *is* runnable locally is the
monitoring/alerting layer and the dashboard generator, so this driver stands up
a mock InfluxDB + mock Slack webhook on one loopback port and runs the REAL
production scripts against it.

Stdlib only. No Docker, no InfluxDB, no Grafana, no network (except `live`).

Commands:
    stack       Start the mock InfluxDB + Slack server and block (manual poking)
    alerts      Run check-soil-moisture.sh + check-sensor-health.sh vs the mock
    dashboard   validate-config.py -> generate-dashboard.py, diff vs committed
    firmware    pio run (compile check, both envs)
    live        Read-only probes against the real Pi / public Grafana
    smoke       dashboard + every alert scenario + a summary table

Run `driver.py <command> --help` for per-command flags.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# Repo root: <repo>/.claude/skills/run-soil-sensor/driver.py -> up 3
REPO = Path(__file__).resolve().parents[3]
SCRIPTS = REPO / "scripts"
RPI_SCRIPTS = REPO / "rpi-setup" / "scripts"
CONFIG = REPO / "sensors-config.json"
MAIN_DASHBOARD = REPO / "grafana-dashboards" / "soil-moisture-main.json"

TOKEN = "driver-test-token"
ORG = "soil-monitoring"
BUCKET = "sensor-readings"

G, Y, R, B, DIM, X = (
    "\033[92m", "\033[93m", "\033[91m", "\033[94m", "\033[2m", "\033[0m",
)


def hdr(text: str) -> None:
    print(f"\n{B}{'=' * 68}\n{text}\n{'=' * 68}{X}", flush=True)


# ────────────────────────────────────────────────────────────────────────────
# Scenarios — what the mock InfluxDB reports
#
# Each entry maps device_id -> (value, age_in_minutes). Soil sensors report
# `moisture` on measurement sensor_reading; climate sensors report `humidity`
# on climate_reading. Ages drive check-sensor-health.sh (>15 min = down);
# values drive check-soil-moisture.sh (<50% = dry).
# ────────────────────────────────────────────────────────────────────────────
SOIL = [f"sensor-{i}" for i in range(1, 8)]
CLIMATE = ["sensor-8", "sensor-9"]

SCENARIOS: dict[str, dict] = {
    "healthy": {
        "expect": {"moisture": 0, "health": 0},
        "desc": "every sensor fresh and above threshold",
        "soil": {s: (72.0 + i * 3, 2) for i, s in enumerate(SOIL)},
        "climate": {s: (46.0, 3) for s in CLIMATE},
    },
    "dry": {
        "expect": {"moisture": 1, "health": 0},
        "desc": "sensor-4 and sensor-7 below the 50% moisture threshold",
        "soil": {
            **{s: (72.0 + i * 3, 2) for i, s in enumerate(SOIL)},
            "sensor-4": (28.4, 2),
            "sensor-7": (41.9, 4),
        },
        "climate": {s: (46.0, 3) for s in CLIMATE},
    },
    "recovered": {
        "expect": {"moisture": 0, "health": 0},
        "desc": "previously-dry plants back above threshold+hysteresis (re-arm)",
        "soil": {**{s: (72.0 + i * 3, 2) for i, s in enumerate(SOIL)},
                 "sensor-4": (61.0, 2), "sensor-7": (58.0, 2)},
        "climate": {s: (46.0, 3) for s in CLIMATE},
    },
    "stale": {
        "expect": {"moisture": 0, "health": 1},
        "desc": "sensor-3 silent 3h, sensor-9 silent 40m (partial outage)",
        "soil": {**{s: (72.0 + i * 3, 2) for i, s in enumerate(SOIL)},
                 "sensor-3": (68.0, 185)},
        "climate": {"sensor-8": (46.0, 3), "sensor-9": (44.0, 40)},
    },
    "all-down": {
        "expect": {"moisture": 0, "health": 2},
        "desc": "every sensor silent for hours -> SYSTEM DOWN "
                "(moisture check stays 0: stale readings are a health problem)",
        "soil": {s: (70.0, 300) for s in SOIL},
        "climate": {s: (46.0, 300) for s in CLIMATE},
    },
    "no-data": {
        "expect": {"moisture": 0, "health": 2},
        "desc": "InfluxDB answers but the bucket is empty",
        "soil": {},
        "climate": {},
    },
    "auth-fail": {
        "expect": {"moisture": 2, "health": 2},
        "desc": "query returns HTTP 401 (expired read token)",
        "soil": {}, "climate": {}, "query_status": 401,
    },
    "influx-down": {
        # Both endpoints fail: check-sensor-health.sh gates on /health, but
        # check-soil-moisture.sh never calls it and only notices via the query.
        "desc": "InfluxDB entirely down (health 503 + query 503)",
        "soil": {}, "climate": {},
        "health_status": 503, "query_status": 503,
        "expect": {"moisture": 2, "health": 2},
    },
    "stuck": {
        "expect": {"moisture": 0, "health": 0},
        "desc": "sensor-2 flatlined -> --check-quality flags it",
        "soil": {s: (72.0 + i * 3, 2) for i, s in enumerate(SOIL)},
        "climate": {s: (46.0, 3) for s in CLIMATE},
        "stddev": {**{s: 2.4 for s in SOIL}, "sensor-2": 0.02},
    },
}


# ────────────────────────────────────────────────────────────────────────────
# Mock server: InfluxDB 2.x subset + Slack webhook sink, one port
# ────────────────────────────────────────────────────────────────────────────
def _rfc3339(minutes_ago: float) -> str:
    t = datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)
    return t.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _annotated_csv(rows: list[tuple[str, str, float]]) -> str:
    """InfluxDB annotated-CSV with device_id/_time/_value, as influx-lib parses."""
    out = [
        "#datatype,string,long,dateTime:RFC3339,double,string",
        "#group,false,false,false,false,true",
        "#default,_result,,,,",
        ",result,table,_time,_value,device_id",
    ]
    for i, (dev, ts, val) in enumerate(rows):
        out.append(f",,{i},{ts},{val},{dev}")
    return "\r\n".join(out) + "\r\n\r\n"


def _stddev_csv(pairs: list[tuple[str, float]]) -> str:
    out = [
        "#datatype,string,long,double,string",
        "#group,false,false,false,true",
        "#default,_result,,,",
        ",result,table,_value,device_id",
    ]
    for i, (dev, val) in enumerate(pairs):
        out.append(f",,{i},{val},{dev}")
    return "\r\n".join(out) + "\r\n\r\n"


class MockState:
    def __init__(self, scenario: str):
        if scenario not in SCENARIOS:
            raise SystemExit(f"unknown scenario '{scenario}' "
                             f"(have: {', '.join(SCENARIOS)})")
        self.name = scenario
        self.spec = SCENARIOS[scenario]
        self.slack: list[dict] = []
        self.queries: list[str] = []
        self.writes: list[str] = []
        self.lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    state: MockState  # set on the server class

    def log_message(self, *_args):  # silence stderr access log
        pass

    def _send(self, code: int, body: str, ctype="text/plain"):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    # -- InfluxDB ----------------------------------------------------------
    def do_GET(self):
        st = self.server.state
        if self.path.startswith("/health"):
            code = st.spec.get("health_status", 200)
            if code != 200:
                return self._send(code, '{"status":"fail","message":"mock down"}',
                                  "application/json")
            return self._send(200, '{"name":"influxdb","status":"pass",'
                                   '"version":"2.7.mock"}', "application/json")
        if self.path == "/slack/captured":
            with st.lock:
                return self._send(200, json.dumps(st.slack), "application/json")
        return self._send(404, "not found")

    def do_POST(self):
        st = self.server.state
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode("utf-8", "replace")

        if self.path.startswith("/slack/webhook"):
            with st.lock:
                try:
                    st.slack.append(json.loads(body))
                except json.JSONDecodeError:
                    st.slack.append({"_malformed_json": body})
            return self._send(200, "ok")

        if self.path.startswith("/api/v2/write"):
            with st.lock:
                st.writes.append(body)
            return self._send(204, "")

        if self.path.startswith("/api/v2/query"):
            forced = st.spec.get("query_status", 200)
            if forced != 200:
                return self._send(forced, '{"code":"unauthorized",'
                                          '"message":"mock: bad token"}',
                                  "application/json")
            auth = self.headers.get("Authorization", "")
            if auth != f"Token {TOKEN}":
                return self._send(401, '{"code":"unauthorized",'
                                       '"message":"mock: bad token"}',
                                  "application/json")
            with st.lock:
                st.queries.append(body)
            return self._send(200, self._answer(body), "text/csv")

        return self._send(404, "not found")

    def _answer(self, flux: str) -> str:
        """Answer a Flux query by pattern-matching the shapes the repo emits."""
        spec = self.server.state.spec
        if "stddev()" in flux:
            sd = spec.get("stddev") or {s: 2.4 for s in spec.get("soil", {})}
            return _stddev_csv(sorted(sd.items()))

        rows: list[tuple[str, str, float]] = []
        wants_soil = 'sensor_reading' in flux
        wants_climate = 'climate_reading' in flux
        # range(start: -Nm|-Nh) — readings older than the window are invisible,
        # exactly like the real database.
        m = re.search(r"range\(start:\s*-(\d+)([mh])\)", flux)
        window = float("inf")
        if m:
            window = int(m.group(1)) * (60 if m.group(2) == "h" else 1)

        if wants_soil:
            for dev, (val, age) in sorted(spec.get("soil", {}).items()):
                if age <= window:
                    rows.append((dev, _rfc3339(age), val))
        if wants_climate:
            for dev, (val, age) in sorted(spec.get("climate", {}).items()):
                if age <= window:
                    rows.append((dev, _rfc3339(age), val))
        return _annotated_csv(rows)


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def start_mock(scenario: str) -> tuple[ThreadingHTTPServer, str, MockState]:
    state = MockState(scenario)
    port = free_port()
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    srv.state = state
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{port}"
    for _ in range(50):  # wait for the socket to answer
        try:
            urllib.request.urlopen(base + "/health", timeout=0.5).read()
            break
        except (urllib.error.HTTPError, urllib.error.URLError, OSError):
            # a 503 scenario still means the server is up
            try:
                urllib.request.urlopen(base + "/slack/captured", timeout=0.5).read()
                break
            except OSError:
                time.sleep(0.05)
    return srv, base, state


# ────────────────────────────────────────────────────────────────────────────
# alerts
# ────────────────────────────────────────────────────────────────────────────
def script_env(base: str, workdir: Path) -> dict:
    env = dict(os.environ)
    env.update(
        INFLUX_URL=base,
        INFLUX_ORG=ORG,
        INFLUX_BUCKET=BUCKET,
        INFLUX_TOKEN=TOKEN,
        SENSORS_CONFIG=str(CONFIG),
        MONITOR_STATE_DIR=str(workdir / "monitor-state"),
        SLACK_SCRIPT=str(SCRIPTS / "send-slack-alert.sh"),
        SLACK_WEBHOOK_URL=f"{base}/slack/webhook",
        SLACK_WEBHOOK_FILE=str(workdir / "no-such-webhook-file"),
        RATE_LIMIT_DIR=str(workdir / "slack-rate-limit"),
        # keep the scripts' own colour codes out of captured output
        TERM="dumb",
    )
    return env


def run_script(path: Path, args: list[str], env: dict) -> subprocess.CompletedProcess:
    print(f"{DIM}$ {path.relative_to(REPO)} {' '.join(args)}{X}")
    p = subprocess.run([str(path), *args], env=env, cwd=str(REPO),
                       capture_output=True, text=True)
    sys.stdout.write(p.stdout)
    if p.stderr.strip():
        sys.stdout.write(f"{DIM}{p.stderr}{X}")
    print(f"{DIM}exit={p.returncode}{X}")
    return p


def show_slack(state: MockState, since: int = 0) -> int:
    with state.lock:
        posts = state.slack[since:]
    if not posts:
        print(f"{DIM}(no Slack posts captured){X}")
        return 0
    for p in posts:
        for att in p.get("attachments", [{}]):
            print(f"{Y}  ┌ SLACK {att.get('title', '(no title)')}{X}")
            for line in (att.get("text") or "").split("\n"):
                print(f"{Y}  │{X} {line}")
            print(f"{Y}  └ color={att.get('color')}{X}")
    return len(posts)


def cmd_alerts(a) -> int:
    workdir = Path(a.workdir or (REPO / ".claude/skills/run-soil-sensor/.work"))
    if a.clean_state and workdir.exists():
        shutil.rmtree(workdir)
    (workdir / "monitor-state").mkdir(parents=True, exist_ok=True)
    (workdir / "slack-rate-limit").mkdir(parents=True, exist_ok=True)

    srv, base, state = start_mock(a.scenario)
    env = script_env(base, workdir)
    hdr(f"scenario: {a.scenario} — {SCENARIOS[a.scenario]['desc']}\n"
        f"mock influx: {base}   slack sink: {base}/slack/webhook\n"
        f"state dir:   {workdir}")

    rc = 0
    seen: dict[str, int] = {}
    try:
        if a.check in ("moisture", "both"):
            hdr("check-soil-moisture.sh")
            extra = [] if a.no_notify else (["--dry-run"] if a.dry_run else ["--notify"])
            before = len(state.slack)
            p = run_script(RPI_SCRIPTS / "check-soil-moisture.sh",
                           ["--verbose", *extra, *a.extra], env)
            seen["moisture"] = p.returncode
            print(f"{B}Slack captured:{X}")
            show_slack(state, before)

        if a.check in ("health", "both"):
            hdr("check-sensor-health.sh")
            extra = [] if a.no_notify else (["--dry-run"] if a.dry_run else ["--notify"])
            before = len(state.slack)
            p = run_script(RPI_SCRIPTS / "check-sensor-health.sh",
                           ["--verbose", "--check-quality", *extra, *a.extra], env)
            seen["health"] = p.returncode
            print(f"{B}Slack captured:{X}")
            show_slack(state, before)
    finally:
        srv.shutdown()

    with state.lock:
        print(f"\n{B}queries seen:{X} {len(state.queries)}   "
              f"{B}slack posts:{X} {len(state.slack)}")

    # Exit codes ARE the contract these scripts expose to systemd, so a scenario
    # that declares `expect` is a regression test, not just a crash check.
    expect = SCENARIOS[a.scenario].get("expect", {})
    for which, got in sorted(seen.items()):
        want = expect.get(which)
        if want is None:
            print(f"  {DIM}{which}: exit {got} (no expectation recorded){X}")
        elif want == got:
            print(f"  {G}✓{X} {which}: exit {got} as expected")
        else:
            print(f"  {R}✗{X} {which}: exit {got}, expected {want}")
            rc = 1
    return rc


# ────────────────────────────────────────────────────────────────────────────
# dashboard
# ────────────────────────────────────────────────────────────────────────────
def panel_inventory(path: Path) -> list[str]:
    d = json.loads(path.read_text())
    out = []
    for p in d.get("panels", []):
        out.append(f"{p.get('id')}\t{p.get('type')}\t{p.get('title')}")
        for sub in p.get("panels", []) or []:
            out.append(f"  {sub.get('id')}\t{sub.get('type')}\t{sub.get('title')}")
    return out


def cmd_dashboard(a) -> int:
    hdr("validate-config.py")
    v = subprocess.run([sys.executable, str(SCRIPTS / "validate-config.py")],
                       capture_output=True, text=True, cwd=str(REPO))
    sys.stdout.write(v.stdout + v.stderr)
    if v.returncode != 0:
        print(f"{R}config invalid — stopping{X}")
        return 1

    # generate-dashboard.py writes IN PLACE into the repo. Snapshot and restore
    # unless --write, so a read-only inspection never dirties the tree.
    backup = MAIN_DASHBOARD.read_bytes() if MAIN_DASHBOARD.exists() else None
    before = panel_inventory(MAIN_DASHBOARD) if backup else []

    hdr("generate-dashboard.py")
    g = subprocess.run([sys.executable, str(SCRIPTS / "generate-dashboard.py")],
                       capture_output=True, text=True, cwd=str(REPO))
    sys.stdout.write(g.stdout + g.stderr)
    if g.returncode != 0:
        if backup is not None:
            MAIN_DASHBOARD.write_bytes(backup)
        return 1

    after = panel_inventory(MAIN_DASHBOARD)
    changed = MAIN_DASHBOARD.read_bytes() != backup

    hdr(f"panels: {len(after)}  ({'CHANGED' if changed else 'identical'} "
        f"vs committed)")
    for line in after:
        print("  " + line)

    if changed:
        added = [l for l in after if l not in before]
        removed = [l for l in before if l not in after]
        for l in removed:
            print(f"{R}  - {l}{X}")
        for l in added:
            print(f"{G}  + {l}{X}")
        if not added and not removed:
            print(f"{Y}  (same panel set; panel bodies differ){X}")

    if a.write:
        print(f"\n{Y}--write: left regenerated dashboard on disk{X}")
    elif backup is not None:
        MAIN_DASHBOARD.write_bytes(backup)
        print(f"\n{DIM}restored committed {MAIN_DASHBOARD.name} "
              f"(pass --write to keep the regenerated file){X}")
    return 0


# ────────────────────────────────────────────────────────────────────────────
# firmware
# ────────────────────────────────────────────────────────────────────────────
def cmd_firmware(a) -> int:
    pio = shutil.which("pio") or shutil.which("platformio")
    if not pio:
        print(f"{R}pio not on PATH — pip install platformio{X}")
        return 127
    hdr(f"pio run -e {a.env}")
    p = subprocess.run([pio, "run", "-e", a.env], cwd=str(REPO / "firmware"))
    return p.returncode


# ────────────────────────────────────────────────────────────────────────────
# live (read-only)
# ────────────────────────────────────────────────────────────────────────────
def probe(label: str, url: str, timeout=8) -> bool:
    """Probe with curl, not urllib.

    The python.org Python on macOS ships without a CA bundle, so urllib fails
    the https://soil.owenmedeiros.com probe with CERTIFICATE_VERIFY_FAILED even
    though the host is perfectly healthy. curl uses the system trust store.
    """
    p = subprocess.run(
        ["curl", "-s", "--max-time", str(timeout), "-w", "\n%{http_code}", url],
        capture_output=True, text=True)
    if p.returncode != 0:
        print(f"  {R}✗{X} {label}: curl rc={p.returncode} {p.stderr.strip()}")
        return False
    *body_lines, code = p.stdout.splitlines() or [""]
    body = " ".join(l.strip() for l in body_lines)
    ok = code == "200"
    mark = f"{G}✓{X}" if ok else f"{R}✗{X}"
    print(f"  {mark} {label}: HTTP {code} {DIM}{body[:150]}{X}")
    return ok


def cmd_live(a) -> int:
    hdr("live read-only probes (never writes, never deploys)")
    ok = True
    ok &= probe("public grafana", "https://soil.owenmedeiros.com/api/health")
    ok &= probe("pi grafana", f"http://{a.pi}:3000/api/health")
    ok &= probe("pi influxdb", f"http://{a.pi}:8086/health")
    print(f"\n{DIM}dashboard panel health (needs a Grafana read token):{X}")
    print(f"{DIM}  ./scripts/check-grafana-panels.py --url http://{a.pi}:3000{X}")
    return 0 if ok else 1


# ────────────────────────────────────────────────────────────────────────────
# smoke
# ────────────────────────────────────────────────────────────────────────────
def cmd_smoke(a) -> int:
    results = []
    rc = cmd_dashboard(argparse.Namespace(write=False))
    results.append(("dashboard", rc))

    for scen in ["healthy", "dry", "stale", "all-down", "influx-down",
                 "auth-fail", "no-data", "stuck"]:
        ns = argparse.Namespace(scenario=scen, check="both", dry_run=True,
                                no_notify=False, workdir=None, clean_state=True,
                                extra=[])
        results.append((f"alerts:{scen}", cmd_alerts(ns)))

    hdr("smoke summary")
    bad = 0
    for name, r in results:
        mark = f"{G}ok{X}" if r == 0 else f"{R}rc={r}{X}"
        bad += r != 0
        print(f"  {mark:>14}  {name}")
    return 1 if bad else 0


# ────────────────────────────────────────────────────────────────────────────
def cmd_stack(a) -> int:
    workdir = Path(a.workdir or (REPO / ".claude/skills/run-soil-sensor/.work"))
    (workdir / "monitor-state").mkdir(parents=True, exist_ok=True)
    (workdir / "slack-rate-limit").mkdir(parents=True, exist_ok=True)
    srv, base, state = start_mock(a.scenario)
    hdr(f"mock stack up — scenario '{a.scenario}'")
    print("Paste into a shell to drive the real scripts by hand:\n")
    for k, v in sorted(script_env(base, workdir).items()):
        if k in {"INFLUX_URL", "INFLUX_ORG", "INFLUX_BUCKET", "INFLUX_TOKEN",
                 "SENSORS_CONFIG", "MONITOR_STATE_DIR", "SLACK_SCRIPT",
                 "SLACK_WEBHOOK_URL", "SLACK_WEBHOOK_FILE", "RATE_LIMIT_DIR"}:
            print(f"  export {k}='{v}'")
    print(f"\n  curl -s {base}/health")
    print(f"  curl -s {base}/slack/captured | jq .")
    print(f"\n{DIM}Ctrl-C to stop.{X}", flush=True)
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        srv.shutdown()
        print(f"\n{B}captured {len(state.slack)} slack post(s), "
              f"{len(state.queries)} query/queries{X}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add_mock_args(p):
        p.add_argument("--scenario", default="healthy", choices=list(SCENARIOS))
        p.add_argument("--workdir", default=None,
                       help="state/rate-limit dir (default: skill .work/)")

    p = sub.add_parser("stack", help="start mock InfluxDB+Slack and block")
    add_mock_args(p)
    p.set_defaults(fn=cmd_stack)

    p = sub.add_parser("alerts", help="run the monitoring scripts vs the mock")
    add_mock_args(p)
    p.add_argument("--check", default="both", choices=["both", "moisture", "health"])
    p.add_argument("--dry-run", action="store_true",
                   help="pass --dry-run to the scripts (no webhook POST, no state)")
    p.add_argument("--no-notify", action="store_true",
                   help="run the check with notifications off entirely")
    p.add_argument("--clean-state", action="store_true",
                   help="wipe state/rate-limit dirs first (fresh edge-trigger)")
    p.add_argument("extra", nargs="*", default=[],
                   help="extra flags forwarded to the check script")
    p.set_defaults(fn=cmd_alerts)

    p = sub.add_parser("dashboard", help="validate + generate + diff panels")
    p.add_argument("--write", action="store_true",
                   help="keep the regenerated dashboard JSON on disk")
    p.set_defaults(fn=cmd_dashboard)

    p = sub.add_parser("firmware", help="pio run compile check")
    p.add_argument("--env", default="esp8266", choices=["esp8266", "esp8266-ota"])
    p.set_defaults(fn=cmd_firmware)

    p = sub.add_parser("live", help="read-only probes of the real Pi/Grafana")
    p.add_argument("--pi", default="192.168.99.134")
    p.set_defaults(fn=cmd_live)

    p = sub.add_parser("smoke", help="dashboard + all alert scenarios")
    p.set_defaults(fn=cmd_smoke)

    a = ap.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
