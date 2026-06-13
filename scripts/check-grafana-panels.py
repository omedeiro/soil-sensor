#!/usr/bin/env python3
"""
check-grafana-panels.py
Grafana Panel Health Checker with API Integration

Connects to Grafana API, enumerates dashboards and panels, tests queries
against InfluxDB, and generates detailed health reports.

Usage:
    ./check-grafana-panels.py
    ./check-grafana-panels.py --dashboard soil-moisture-main-v2
    ./check-grafana-panels.py --format json > report.json
    ./check-grafana-panels.py --verbose
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
from urllib.parse import urljoin

try:
    import requests
    from requests.auth import HTTPBasicAuth
except ImportError:
    print("ERROR: 'requests' library not found", file=sys.stderr)
    print("Install with: pip3 install requests", file=sys.stderr)
    sys.exit(1)

# Configuration
GRAFANA_URL = os.getenv('GRAFANA_URL', 'http://192.168.99.134:3000')
GRAFANA_USER = os.getenv('GRAFANA_USER', 'admin')
GRAFANA_PASSWORD = os.getenv('GRAFANA_PASSWORD', 'admin')

INFLUX_URL = os.getenv('INFLUX_URL', 'http://192.168.99.134:8086')
INFLUX_ORG = os.getenv('INFLUX_ORG', 'soil-monitoring')
INFLUX_BUCKET = os.getenv('INFLUX_BUCKET', 'sensor-readings')
INFLUX_TOKEN = os.getenv('INFLUX_TOKEN', 'r7LONiwdc3ABOcEYSS5nCL6c6sdUZEPy81Q1D7w7nAyXZDAteUD1C6BYZJe21qX4eOwhRvG2ARYwRkaHwQf17w==')

# Status constants
STATUS_HEALTHY = 'healthy'
STATUS_NO_DATA = 'no_data'
STATUS_QUERY_ERROR = 'query_error'
STATUS_DATASOURCE_ERROR = 'datasource_error'
STATUS_UNKNOWN = 'unknown'

# Color codes for terminal output
COLOR_GREEN = '\033[92m'
COLOR_YELLOW = '\033[93m'
COLOR_RED = '\033[91m'
COLOR_BLUE = '\033[94m'
COLOR_RESET = '\033[0m'


class GrafanaPanelChecker:
    """Check health of Grafana panels by testing their queries"""
    
    def __init__(self, grafana_url: str, username: str, password: str, 
                 influx_url: str, influx_token: str, influx_org: str,
                 verbose: bool = False):
        self.grafana_url = grafana_url.rstrip('/')
        self.auth = HTTPBasicAuth(username, password)
        self.influx_url = influx_url.rstrip('/')
        self.influx_token = influx_token
        self.influx_org = influx_org
        self.verbose = verbose
        self.session = requests.Session()
        
    def log(self, message: str, level: str = 'INFO'):
        """Log message if verbose mode enabled"""
        if self.verbose:
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            print(f"[{timestamp}] {level}: {message}", file=sys.stderr)
    
    def get_dashboards(self, dashboard_uid: Optional[str] = None) -> List[Dict]:
        """Get list of dashboards from Grafana"""
        if dashboard_uid:
            self.log(f"Fetching dashboard: {dashboard_uid}")
            url = f"{self.grafana_url}/api/dashboards/uid/{dashboard_uid}"
            response = self.session.get(url, auth=self.auth, timeout=10)
            response.raise_for_status()
            dashboard_data = response.json()
            return [{
                'uid': dashboard_data['dashboard']['uid'],
                'title': dashboard_data['dashboard']['title'],
                'url': dashboard_data['meta']['url']
            }]
        else:
            self.log("Fetching all dashboards")
            url = f"{self.grafana_url}/api/search?type=dash-db"
            response = self.session.get(url, auth=self.auth, timeout=10)
            response.raise_for_status()
            return response.json()
    
    def get_dashboard_details(self, dashboard_uid: str) -> Dict:
        """Get full dashboard details including panels"""
        self.log(f"Fetching dashboard details: {dashboard_uid}")
        url = f"{self.grafana_url}/api/dashboards/uid/{dashboard_uid}"
        response = self.session.get(url, auth=self.auth, timeout=10)
        response.raise_for_status()
        return response.json()
    
    def extract_queries_from_panel(self, panel: Dict) -> List[Dict]:
        """Extract InfluxDB queries from panel configuration"""
        queries = []
        
        if 'targets' not in panel:
            return queries
        
        for target in panel['targets']:
            if target.get('hide'):
                continue
                
            query_text = target.get('query', '')
            
            # Handle Flux queries
            if query_text:
                queries.append({
                    'query': query_text,
                    'ref_id': target.get('refId', ''),
                    'datasource': target.get('datasource', {})
                })
        
        return queries
    
    def test_influx_query(self, query: str) -> Tuple[str, int, Optional[str], float]:
        """
        Test Flux query against InfluxDB
        
        Returns:
            (status, data_points, error_message, query_time)
        """
        start_time = time.time()
        
        try:
            url = f"{self.influx_url}/api/v2/query?org={self.influx_org}"
            headers = {
                'Authorization': f'Token {self.influx_token}',
                'Content-Type': 'application/vnd.flux',
                'Accept': 'application/csv'
            }
            
            response = self.session.post(url, headers=headers, data=query, timeout=30)
            query_time = time.time() - start_time
            
            if response.status_code == 200:
                # Parse CSV response to count data points
                lines = response.text.strip().split('\n')
                # Filter out header lines and empty lines
                data_lines = [line for line in lines if line and not line.startswith('#')]
                # Subtract 1 for CSV header row
                data_points = max(0, len(data_lines) - 1)
                
                if data_points == 0:
                    return STATUS_NO_DATA, 0, None, query_time
                else:
                    return STATUS_HEALTHY, data_points, None, query_time
            elif response.status_code == 401:
                return STATUS_DATASOURCE_ERROR, 0, "Unauthorized - invalid token", query_time
            else:
                error_msg = response.text[:200]  # Truncate long errors
                return STATUS_QUERY_ERROR, 0, error_msg, query_time
                
        except requests.exceptions.Timeout:
            query_time = time.time() - start_time
            return STATUS_QUERY_ERROR, 0, "Query timeout (>30s)", query_time
        except requests.exceptions.ConnectionError:
            query_time = time.time() - start_time
            return STATUS_DATASOURCE_ERROR, 0, "Connection refused - InfluxDB unreachable", query_time
        except Exception as e:
            query_time = time.time() - start_time
            return STATUS_QUERY_ERROR, 0, str(e), query_time
    
    def check_panel(self, panel: Dict) -> Dict:
        """Check health of a single panel"""
        panel_id = panel.get('id', 'unknown')
        panel_title = panel.get('title', 'Untitled')
        panel_type = panel.get('type', 'unknown')
        
        self.log(f"Checking panel: {panel_title} (ID: {panel_id}, Type: {panel_type})")
        
        result = {
            'id': panel_id,
            'title': panel_title,
            'type': panel_type,
            'status': STATUS_UNKNOWN,
            'data_points': 0,
            'query_time': 0.0,
            'queries': [],
            'error': None
        }
        
        # Skip panels without queries (text panels, etc.)
        if panel_type in ['text', 'row']:
            result['status'] = 'skipped'
            return result
        
        queries = self.extract_queries_from_panel(panel)
        
        if not queries:
            result['status'] = 'no_query'
            result['error'] = 'No queries found in panel'
            return result
        
        # Test each query and aggregate results
        all_healthy = True
        total_data_points = 0
        total_query_time = 0.0
        errors = []
        
        for query_info in queries:
            query_text = query_info['query']
            
            if not query_text or query_text.strip() == '':
                continue
            
            status, data_points, error, query_time = self.test_influx_query(query_text)
            
            result['queries'].append({
                'ref_id': query_info['ref_id'],
                'query': query_text[:100] + '...' if len(query_text) > 100 else query_text,
                'status': status,
                'data_points': data_points,
                'query_time': query_time
            })
            
            total_data_points += data_points
            total_query_time += query_time
            
            if status != STATUS_HEALTHY:
                all_healthy = False
                if error:
                    errors.append(f"{query_info['ref_id']}: {error}")
        
        # Determine overall panel status
        if all_healthy and total_data_points > 0:
            result['status'] = STATUS_HEALTHY
        elif total_data_points == 0:
            result['status'] = STATUS_NO_DATA
        elif errors:
            result['status'] = STATUS_QUERY_ERROR
            result['error'] = '; '.join(errors)
        
        result['data_points'] = total_data_points
        result['query_time'] = round(total_query_time, 3)
        
        return result
    
    def check_dashboard(self, dashboard_uid: str) -> Dict:
        """Check all panels in a dashboard"""
        dashboard_details = self.get_dashboard_details(dashboard_uid)
        dashboard_data = dashboard_details['dashboard']
        
        result = {
            'uid': dashboard_data['uid'],
            'title': dashboard_data['title'],
            'url': f"{self.grafana_url}{dashboard_details['meta']['url']}",
            'panels': []
        }
        
        # Recursively find all panels (including nested panels in rows)
        def extract_panels(panels: List[Dict]) -> List[Dict]:
            all_panels = []
            for panel in panels:
                if panel.get('type') == 'row' and 'panels' in panel:
                    all_panels.extend(extract_panels(panel['panels']))
                else:
                    all_panels.append(panel)
            return all_panels
        
        panels = extract_panels(dashboard_data.get('panels', []))
        
        for panel in panels:
            panel_result = self.check_panel(panel)
            result['panels'].append(panel_result)
        
        return result
    
    def check_all_dashboards(self, dashboard_uid: Optional[str] = None) -> Dict:
        """Check all dashboards and generate report"""
        dashboards = self.get_dashboards(dashboard_uid)
        
        report = {
            'timestamp': datetime.now().isoformat(),
            'grafana_url': self.grafana_url,
            'influx_url': self.influx_url,
            'summary': {
                'total_dashboards': len(dashboards),
                'total_panels': 0,
                'healthy': 0,
                'no_data': 0,
                'query_error': 0,
                'datasource_error': 0,
                'skipped': 0
            },
            'dashboards': []
        }
        
        for dashboard in dashboards:
            try:
                dashboard_result = self.check_dashboard(dashboard['uid'])
                report['dashboards'].append(dashboard_result)
                
                # Update summary
                for panel in dashboard_result['panels']:
                    report['summary']['total_panels'] += 1
                    status = panel['status']
                    
                    if status == STATUS_HEALTHY:
                        report['summary']['healthy'] += 1
                    elif status == STATUS_NO_DATA:
                        report['summary']['no_data'] += 1
                    elif status == STATUS_QUERY_ERROR:
                        report['summary']['query_error'] += 1
                    elif status == STATUS_DATASOURCE_ERROR:
                        report['summary']['datasource_error'] += 1
                    elif status in ['skipped', 'no_query']:
                        report['summary']['skipped'] += 1
                        
            except Exception as e:
                self.log(f"Error checking dashboard {dashboard['uid']}: {e}", 'ERROR')
                report['dashboards'].append({
                    'uid': dashboard['uid'],
                    'title': dashboard.get('title', 'Unknown'),
                    'error': str(e),
                    'panels': []
                })
        
        return report


def format_report_human(report: Dict) -> str:
    """Format report for human-readable terminal output"""
    lines = []
    
    # Header
    lines.append("=" * 80)
    lines.append("GRAFANA PANEL HEALTH REPORT")
    lines.append("=" * 80)
    lines.append(f"Timestamp: {report['timestamp']}")
    lines.append(f"Grafana:   {report['grafana_url']}")
    lines.append(f"InfluxDB:  {report['influx_url']}")
    lines.append("")
    
    # Summary
    summary = report['summary']
    lines.append("SUMMARY")
    lines.append("-" * 80)
    lines.append(f"Total Dashboards: {summary['total_dashboards']}")
    lines.append(f"Total Panels:     {summary['total_panels']}")
    lines.append(f"{COLOR_GREEN}✓ Healthy:        {summary['healthy']}{COLOR_RESET}")
    lines.append(f"{COLOR_YELLOW}✗ No Data:        {summary['no_data']}{COLOR_RESET}")
    lines.append(f"{COLOR_RED}⚠ Query Errors:   {summary['query_error']}{COLOR_RESET}")
    lines.append(f"{COLOR_RED}🔴 DB Errors:      {summary['datasource_error']}{COLOR_RESET}")
    lines.append(f"⊘ Skipped:        {summary['skipped']}")
    lines.append("")
    
    # Dashboard details
    for dashboard in report['dashboards']:
        if 'error' in dashboard:
            lines.append(f"{COLOR_RED}Dashboard: {dashboard['title']} (ERROR){COLOR_RESET}")
            lines.append(f"  Error: {dashboard['error']}")
            lines.append("")
            continue
        
        lines.append(f"Dashboard: {dashboard['title']}")
        lines.append(f"URL:       {dashboard['url']}")
        lines.append("")
        
        # Group panels by status
        healthy = [p for p in dashboard['panels'] if p['status'] == STATUS_HEALTHY]
        no_data = [p for p in dashboard['panels'] if p['status'] == STATUS_NO_DATA]
        errors = [p for p in dashboard['panels'] if p['status'] in [STATUS_QUERY_ERROR, STATUS_DATASOURCE_ERROR]]
        
        if healthy:
            lines.append(f"  {COLOR_GREEN}✓ Healthy Panels ({len(healthy)}):{COLOR_RESET}")
            for panel in healthy:
                lines.append(f"    • {panel['title']} ({panel['data_points']} points, {panel['query_time']}s)")
        
        if no_data:
            lines.append(f"  {COLOR_YELLOW}✗ No Data Panels ({len(no_data)}):{COLOR_RESET}")
            for panel in no_data:
                lines.append(f"    • {panel['title']} (0 results)")
        
        if errors:
            lines.append(f"  {COLOR_RED}⚠ Error Panels ({len(errors)}):{COLOR_RESET}")
            for panel in errors:
                lines.append(f"    • {panel['title']}")
                if panel.get('error'):
                    lines.append(f"      Error: {panel['error']}")
        
        lines.append("")
    
    lines.append("=" * 80)
    
    # Overall health status
    if summary['no_data'] == 0 and summary['query_error'] == 0 and summary['datasource_error'] == 0:
        lines.append(f"{COLOR_GREEN}✓ All panels healthy!{COLOR_RESET}")
    elif summary['no_data'] > 0 or summary['query_error'] > 0:
        lines.append(f"{COLOR_YELLOW}⚠ {summary['no_data'] + summary['query_error']} panel(s) need attention{COLOR_RESET}")
    
    if summary['datasource_error'] > 0:
        lines.append(f"{COLOR_RED}🔴 CRITICAL: Datasource connection issues detected{COLOR_RESET}")
    
    lines.append("=" * 80)
    
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(
        description='Check health of Grafana panels by testing their queries',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Check all dashboards
  %(prog)s
  
  # Check specific dashboard
  %(prog)s --dashboard soil-moisture-main-v2
  
  # Output JSON for automation
  %(prog)s --format json > report.json
  
  # Verbose mode with query details
  %(prog)s --verbose

Configuration:
  Set via environment variables:
    GRAFANA_URL      (default: http://192.168.99.134:3000)
    GRAFANA_USER     (default: admin)
    GRAFANA_PASSWORD (default: admin)
    INFLUX_URL       (default: http://192.168.99.134:8086)
    INFLUX_TOKEN     (default: embedded token)
    INFLUX_ORG       (default: soil-monitoring)
        """
    )
    
    parser.add_argument('--dashboard', help='Check specific dashboard by UID')
    parser.add_argument('--format', choices=['human', 'json'], default='human',
                        help='Output format (default: human)')
    parser.add_argument('--verbose', action='store_true',
                        help='Verbose output with query details')
    parser.add_argument('--write-influx', action='store_true',
                        help='Write panel health metrics to InfluxDB')
    
    args = parser.parse_args()
    
    try:
        checker = GrafanaPanelChecker(
            GRAFANA_URL, GRAFANA_USER, GRAFANA_PASSWORD,
            INFLUX_URL, INFLUX_TOKEN, INFLUX_ORG,
            verbose=args.verbose
        )
        
        report = checker.check_all_dashboards(args.dashboard)
        
        # Output report
        if args.format == 'json':
            print(json.dumps(report, indent=2))
        else:
            print(format_report_human(report))
        
        # Write to InfluxDB if requested
        if args.write_influx:
            # TODO: Implement InfluxDB write for metrics
            pass
        
        # Exit code based on health
        summary = report['summary']
        if summary['datasource_error'] > 0:
            sys.exit(3)  # Critical: datasource error
        elif summary['query_error'] > 0:
            sys.exit(2)  # Error: query errors
        elif summary['no_data'] > 0:
            sys.exit(1)  # Warning: no data
        else:
            sys.exit(0)  # Success
            
    except KeyboardInterrupt:
        print("\nInterrupted by user", file=sys.stderr)
        sys.exit(130)
    except Exception as e:
        print(f"FATAL ERROR: {e}", file=sys.stderr)
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
