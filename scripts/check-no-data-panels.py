#!/usr/bin/env python3
"""
check-no-data-panels.py
Static "No Data" panel checker for the committed Grafana dashboards.

The panel-health monitor on the Pi (scripts/check-grafana-panels.py) finds
panels that render "No Data" by running their queries against the live
InfluxDB. That needs the Pi, so it cannot run in CI. This checker catches the
*static* causes of a "No Data" panel — the ones that are visible in the
dashboard JSON itself and are almost always the reason a panel goes blank:

  * a datasource UID that is not the InfluxDB datasource in sensors-config.json
  * a panel that has no query at all
  * a query reading a bucket that does not exist
  * a query filtering on a measurement nothing writes
  * a query filtering on `_field` that is not a field of that measurement
    (including the classic case of filtering on something that is a *tag*)
  * a query filtering on a tag/column that does not exist
  * a device_id that is not in sensors-config.json
  * a `from()` stream with no `range()` (Flux rejects it)
  * unbalanced quotes/brackets in a query
  * a `${variable}` that the dashboard does not define

Ground truth for measurements/tags/fields is influx-schema.json, which is
derived from the code that writes each point.

Usage:
    ./check-no-data-panels.py
    ./check-no-data-panels.py --format json
    ./check-no-data-panels.py --dashboard grafana-dashboards/rpi-health.json

Exit codes:
    0 - no problems found (warnings do not fail)
    1 - one or more panels would render "No Data"
    2 - the checker could not run (bad config/schema/dashboard JSON)
"""

import argparse
import fnmatch
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DASHBOARD_DIR = REPO_ROOT / "grafana-dashboards"
DEFAULT_CONFIG = REPO_ROOT / "sensors-config.json"
DEFAULT_SCHEMA = REPO_ROOT / "influx-schema.json"
DEFAULT_ALLOWLIST = REPO_ROOT / "tests" / "no-data-allowlist.json"

# Panel types that legitimately carry no query.
QUERYLESS_PANEL_TYPES = {"row", "text", "dashlist", "news", "alertlist", "welcome"}

# Grafana-provided variables that never appear in a dashboard's templating list.
BUILTIN_VARIABLES = {
    "__interval", "__interval_ms", "__rate_interval", "__range", "__range_s",
    "__range_ms", "__from", "__to", "__timeFilter", "__dashboard", "__org",
    "__user", "__name", "__field", "__series", "__value", "__timezone",
    "timeFilter", "timeGroup",
}

# Flux functions that mint new columns, e.g. elapsed(...) adds an "elapsed"
# column that later filters legitimately reference.
COLUMN_CREATING_DEFAULTS = {"elapsed": "elapsed", "stateDuration": "stateDuration"}

COLOR = {
    "red": "\033[91m", "yellow": "\033[93m", "green": "\033[92m",
    "blue": "\033[94m", "bold": "\033[1m", "reset": "\033[0m",
}

ERROR = "error"
WARNING = "warning"


class Finding:
    def __init__(self, dashboard, panel_id, panel_title, rule, message,
                 severity=ERROR, ref_id=None):
        self.dashboard = dashboard
        self.panel_id = panel_id
        self.panel_title = panel_title
        self.rule = rule
        self.message = message
        self.severity = severity
        self.ref_id = ref_id

    def as_dict(self):
        return {
            "dashboard": self.dashboard,
            "panel_id": self.panel_id,
            "panel_title": self.panel_title,
            "ref_id": self.ref_id,
            "rule": self.rule,
            "severity": self.severity,
            "message": self.message,
        }


def die(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(2)


def load_json(path, what):
    try:
        with open(path) as handle:
            return json.load(handle)
    except FileNotFoundError:
        die(f"{what} not found: {path}")
    except json.JSONDecodeError as exc:
        die(f"{what} is not valid JSON ({path}): {exc}")


def iter_panels(dashboard):
    """Yield every panel, descending into collapsed rows."""
    def walk(panels):
        for panel in panels or []:
            if panel.get("type") == "row":
                yield from walk(panel.get("panels"))
            else:
                yield panel
                # Grafana keeps nested panels on non-row panels in some exports
                if panel.get("panels"):
                    yield from walk(panel.get("panels"))

    yield from walk(dashboard.get("panels"))


def target_query(target):
    """Return the Flux text of a target, whichever shape Grafana stored it in."""
    query = target.get("query")
    if isinstance(query, str):
        return query
    if isinstance(query, dict) and isinstance(query.get("query"), str):
        return query["query"]
    return ""


def collect_datasource_uids(node, found):
    """Collect every influxdb datasource UID anywhere in the dashboard."""
    if isinstance(node, dict):
        if node.get("type") == "influxdb" and isinstance(node.get("uid"), str):
            found.add(node["uid"])
        for value in node.values():
            collect_datasource_uids(value, found)
    elif isinstance(node, list):
        for value in node:
            collect_datasource_uids(value, found)


def split_streams(query):
    """
    Split a Flux query into its `from(bucket: ...)` streams so a field can be
    checked against the measurement of the stream it belongs to, not against
    some other stream in the same query.
    """
    starts = [m.start() for m in re.finditer(r"from\s*\(\s*bucket\s*:", query)]
    if not starts:
        return []
    bounds = starts + [len(query)]
    return [query[bounds[i]:bounds[i + 1]] for i in range(len(starts))]


def created_columns(query):
    """Column names a query mints itself (map/rename/duplicate/elapsed/...)."""
    columns = set()
    # map(fn: (r) => ({name: ..., other: ...}))  and  ({r with name: ...})
    for body in re.findall(r"=>\s*\(\{(.*?)\}\)", query, flags=re.S):
        columns.update(re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*:", body))
    # column: "name" / as: "name" / valueColumn: "name" / timeColumn: "name"
    columns.update(re.findall(r'(?:column|as|valueColumn|timeColumn|newColumn)\s*:\s*"([^"]+)"', query))
    # columns: ["a", "b"]
    for group in re.findall(r"columns\s*:\s*\[([^\]]*)\]", query):
        columns.update(re.findall(r'"([^"]+)"', group))
    # rename(columns: {_value: "moisture"}) / set(key: "x")
    columns.update(re.findall(r'rename\s*\(\s*columns\s*:\s*\{[^}]*?:\s*"([^"]+)"', query))
    columns.update(re.findall(r'key\s*:\s*"([^"]+)"', query))
    # functions that add a default-named column
    for func, column in COLUMN_CREATING_DEFAULTS.items():
        if re.search(rf"\|>\s*{func}\s*\(", query):
            columns.add(column)
    return columns


def balanced(query):
    """Report the first unbalanced bracket/quote kind in a query, if any."""
    in_string = False
    in_line_comment = False
    depth = {"(": 0, "[": 0, "{": 0}
    closers = {")": "(", "]": "[", "}": "{"}
    previous = ""
    for char in query:
        if in_line_comment:
            if char == "\n":
                in_line_comment = False
            previous = char
            continue
        if in_string:
            if char == '"' and previous != "\\":
                in_string = False
            previous = "" if (char == "\\" and previous == "\\") else char
            continue
        if char == '"':
            in_string = True
        elif char == "/" and previous == "/":
            in_line_comment = True
        elif char in depth:
            depth[char] += 1
        elif char in closers:
            depth[closers[char]] -= 1
            if depth[closers[char]] < 0:
                return f"unbalanced '{char}'"
        previous = char
    if in_string:
        return "unterminated string literal"
    for opener, count in depth.items():
        if count > 0:
            return f"unclosed '{opener}'"
    return None


def check_query(query, context, schema, buckets, device_ids, variables):
    """Return findings for one target's Flux query."""
    findings = []
    add = lambda rule, message, severity=ERROR: findings.append(
        Finding(context["dashboard"], context["panel_id"], context["panel_title"],
                rule, message, severity, context.get("ref_id"))
    )

    problem = balanced(query)
    if problem:
        add("unbalanced", f"query has {problem} — Grafana cannot execute it")

    # Undefined dashboard variables.
    used = set(re.findall(r"\$\{([A-Za-z_][A-Za-z0-9_]*)[:.]?[^}]*\}", query))
    used |= set(re.findall(r"\$([A-Za-z_][A-Za-z0-9_]*)", query))
    for name in sorted(used - variables - BUILTIN_VARIABLES):
        add("variable", f"uses ${{{name}}}, which the dashboard does not define")

    streams = split_streams(query)
    if not streams:
        return findings

    known_columns = set(schema["columns"]) | created_columns(query)
    # A pivot renames field values into columns, so column names become dynamic.
    pivots = "pivot(" in query

    query_measurements = set()
    for stream in streams:
        bucket_match = re.search(r'from\s*\(\s*bucket\s*:\s*"([^"]*)"', stream)
        if bucket_match:
            bucket = bucket_match.group(1)
            if bucket not in buckets:
                add("bucket",
                    f'reads bucket "{bucket}"; the configured bucket is '
                    f'"{sorted(buckets)[0]}"')
        elif not re.search(r"from\s*\(\s*bucket\s*:\s*[v$]", stream):
            add("bucket", "from() call has no literal bucket name")

        if not re.search(r"\|>\s*range\s*\(", stream):
            add("missing_range",
                "from() stream has no range() — Flux rejects an unbounded read")

        measurements = set(re.findall(r'_measurement\s*==\s*"([^"]*)"', stream))
        wildcard = bool(re.search(r"_measurement\s*=~", stream))
        for measurement in sorted(measurements):
            if measurement not in schema["measurements"]:
                add("measurement",
                    f'filters on measurement "{measurement}", which nothing in '
                    f"this repo writes")
        query_measurements |= measurements

        valid = {m: schema["measurements"][m] for m in measurements
                 if m in schema["measurements"]}
        if valid and not wildcard:
            allowed_fields = set()
            allowed_tags = set()
            for spec in valid.values():
                allowed_fields |= set(spec["fields"])
                allowed_tags |= set(spec["tags"])
            for field in sorted(set(re.findall(r'_field\s*==\s*"([^"]*)"', stream))):
                if field in allowed_fields:
                    continue
                where = " or ".join(sorted(valid))
                if field in allowed_tags:
                    add("field",
                        f'filters on _field == "{field}", but "{field}" is a TAG '
                        f'of {where}, not a field — this panel is always empty')
                else:
                    add("field",
                        f'filters on _field == "{field}", which {where} does not '
                        f"write (fields: {', '.join(sorted(allowed_fields))})")

    # Tag/column references, checked across the whole query so that columns
    # created in one stream are visible to the filters of another.
    if query_measurements and not pivots:
        allowed = set(known_columns)
        for measurement in query_measurements:
            spec = schema["measurements"].get(measurement)
            if spec:
                allowed |= set(spec["tags"]) | set(spec["fields"])
        for attr in sorted(set(re.findall(r"r\.([A-Za-z_][A-Za-z0-9_]*)", query))):
            if attr.startswith("_") or attr in allowed:
                continue
            add("tag",
                f'filters on r.{attr}, which is not a tag or column of '
                f"{' / '.join(sorted(query_measurements))}")

    # device_id values, literal and inside a regex.
    referenced = set(re.findall(r'device_id\s*==\s*"([^"]*)"', query))
    for group in re.findall(r"device_id\s*=~\s*/([^/]*)/", query):
        referenced |= set(re.findall(r"sensor-\d+", group))
    for device in sorted(referenced):
        if "$" in device or "{" in device:
            continue
        if device not in device_ids:
            add("device_id",
                f'filters on device_id "{device}", which is not in '
                f"sensors-config.json")

    return findings


def check_dashboard(path, schema, buckets, device_ids, datasource_uid):
    dashboard = load_json(path, "Dashboard")
    name = path.name
    findings = []

    uids = set()
    collect_datasource_uids(dashboard, uids)
    for uid in sorted(uids - {datasource_uid}):
        findings.append(Finding(
            name, None, None, "datasource",
            f'uses InfluxDB datasource UID "{uid}"; sensors-config.json '
            f'declares "{datasource_uid}" — every panel on that datasource '
            f"renders No Data"))

    variables = {v.get("name") for v in dashboard.get("templating", {}).get("list", [])
                 if v.get("name")}

    panel_count = 0
    query_count = 0
    for panel in iter_panels(dashboard):
        panel_count += 1
        panel_type = panel.get("type", "unknown")
        panel_id = panel.get("id")
        panel_title = panel.get("title") or "Untitled"
        targets = [t for t in (panel.get("targets") or []) if not t.get("hide")]
        queries = [(t.get("refId"), target_query(t)) for t in targets]
        queries = [(ref, q) for ref, q in queries if q.strip()]

        if not queries:
            if panel_type not in QUERYLESS_PANEL_TYPES:
                findings.append(Finding(
                    name, panel_id, panel_title, "no_query",
                    f"{panel_type} panel has no query — it can only ever show "
                    f"No Data"))
            continue

        for ref_id, query in queries:
            query_count += 1
            findings.extend(check_query(
                query,
                {"dashboard": name, "panel_id": panel_id,
                 "panel_title": panel_title, "ref_id": ref_id},
                schema, buckets, device_ids, variables))

    # Templating queries feed every panel that uses the variable.
    for variable in dashboard.get("templating", {}).get("list", []):
        query = variable.get("query")
        if isinstance(query, dict):
            query = query.get("query")
        if not isinstance(query, str) or "from(bucket" not in query:
            continue
        query_count += 1
        findings.extend(check_query(
            query,
            {"dashboard": name, "panel_id": None,
             "panel_title": f"variable ${variable.get('name')}",
             "ref_id": None},
            schema, buckets, device_ids, variables))

    return findings, panel_count, query_count


def suppressed(finding, allowlist):
    for entry in allowlist:
        if not fnmatch.fnmatch(finding.dashboard, entry.get("dashboard", "*")):
            continue
        if "panel" in entry and entry["panel"] not in (finding.panel_id, finding.panel_title):
            continue
        if "rule" in entry and entry["rule"] != finding.rule:
            continue
        if "match" in entry and entry["match"] not in finding.message:
            continue
        return entry
    return None


def main():
    parser = argparse.ArgumentParser(
        description="Statically check Grafana dashboards for panels that can "
                    "only render \"No Data\".")
    parser.add_argument("--dashboard", action="append", metavar="PATH",
                        help="check only this dashboard file (repeatable)")
    parser.add_argument("--dashboard-dir", default=str(DEFAULT_DASHBOARD_DIR),
                        help="directory of dashboard JSON files")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG),
                        help="path to sensors-config.json")
    parser.add_argument("--schema", default=str(DEFAULT_SCHEMA),
                        help="path to influx-schema.json")
    parser.add_argument("--allowlist", default=str(DEFAULT_ALLOWLIST),
                        help="path to the suppression allowlist")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--no-color", action="store_true")
    args = parser.parse_args()

    use_color = sys.stdout.isatty() and not args.no_color
    paint = (lambda text, color: f"{COLOR[color]}{text}{COLOR['reset']}") if use_color \
        else (lambda text, color: text)

    config = load_json(Path(args.config), "sensors-config.json")
    schema = load_json(Path(args.schema), "influx-schema.json")

    grafana = config.get("grafana") or {}
    datasource_uid = grafana.get("influxdb_datasource_uid")
    bucket = grafana.get("bucket")
    if not datasource_uid or not bucket:
        die("sensors-config.json is missing grafana.influxdb_datasource_uid "
            "or grafana.bucket")

    device_ids = {s.get("id") for s in config.get("sensors", [])}
    device_ids |= {s.get("id") for s in config.get("climate_sensors", [])}

    allowlist = []
    allowlist_path = Path(args.allowlist)
    if allowlist_path.exists():
        allowlist = load_json(allowlist_path, "Allowlist").get("suppressions", [])

    if args.dashboard:
        paths = [Path(p) for p in args.dashboard]
    else:
        paths = sorted(Path(args.dashboard_dir).glob("*.json"))
    if not paths:
        die(f"no dashboards found in {args.dashboard_dir}")

    findings = []
    suppressions = []
    totals = {"dashboards": 0, "panels": 0, "queries": 0}
    for path in paths:
        dash_findings, panels, queries = check_dashboard(
            path, schema, {bucket}, device_ids, datasource_uid)
        totals["dashboards"] += 1
        totals["panels"] += panels
        totals["queries"] += queries
        for finding in dash_findings:
            entry = suppressed(finding, allowlist)
            if entry:
                finding.severity = WARNING
                finding.message += f"  [allowlisted: {entry.get('reason', 'no reason given')}]"
                suppressions.append(finding)
            else:
                findings.append(finding)

    errors = [f for f in findings if f.severity == ERROR]

    if args.format == "json":
        print(json.dumps({
            "summary": {
                "dashboards": totals["dashboards"],
                "panels": totals["panels"],
                "queries": totals["queries"],
                "errors": len(errors),
                "allowlisted": len(suppressions),
            },
            "findings": [f.as_dict() for f in findings],
            "allowlisted": [f.as_dict() for f in suppressions],
        }, indent=2))
        return 1 if errors else 0

    print(paint("Static \"No Data\" panel check", "bold"))
    print(f"  dashboards: {totals['dashboards']}   panels: {totals['panels']}   "
          f"queries: {totals['queries']}")
    print(f"  datasource: {datasource_uid}   bucket: {bucket}")
    print()

    if suppressions:
        print(paint(f"Allowlisted ({len(suppressions)}):", "yellow"))
        for finding in suppressions:
            location = finding.panel_title or finding.dashboard
            print(f"  - [{finding.dashboard}] {location}: {finding.message}")
        print()

    if not errors:
        print(paint("✓ No panels would render \"No Data\"", "green"))
        return 0

    by_dashboard = {}
    for finding in errors:
        by_dashboard.setdefault(finding.dashboard, []).append(finding)

    for dashboard in sorted(by_dashboard):
        print(paint(f"{dashboard}", "blue"))
        for finding in by_dashboard[dashboard]:
            if finding.panel_id is not None:
                location = f"panel {finding.panel_id} \"{finding.panel_title}\""
            elif finding.panel_title:
                location = finding.panel_title
            else:
                location = "dashboard"
            if finding.ref_id:
                location += f" (target {finding.ref_id})"
            print(f"  {paint('✗', 'red')} {location}")
            print(f"      {finding.rule}: {finding.message}")
        print()

    print(paint(f"✗ {len(errors)} problem(s) that would show as \"No Data\"", "red"))
    print("  Fix the query, or — if the data really is written by something "
          "outside this repo —")
    print(f"  add the measurement/field to influx-schema.json, or an entry to "
          f"{DEFAULT_ALLOWLIST.relative_to(REPO_ROOT)}.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
