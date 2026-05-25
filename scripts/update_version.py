#!/usr/bin/env python3
"""
Automated version update script for Soil Moisture Monitoring System.

Updates version numbers across all project files and optionally creates
CHANGELOG entries for new releases.

Usage:
    ./update_version.py 2.7.0                    # Bump version to 2.7.0
    ./update_version.py 2.7.0 --changelog        # Bump version + create CHANGELOG template
    ./update_version.py --current                # Show current version

Features:
    - Updates version in README.md (root)
    - Updates version in grafana-dashboards/README.md
    - Updates dashboard JSON files with new version metadata
    - Optionally creates CHANGELOG.md entry template
    - Validates semantic versioning format
    - Shows diff of changes before applying
"""

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple

# Project root directory
PROJECT_ROOT = Path(__file__).parent.parent

# Files to update with version numbers
VERSION_FILES = {
    "root_readme": PROJECT_ROOT / "README.md",
    "dashboard_readme": PROJECT_ROOT / "grafana-dashboards" / "README.md",
    "changelog": PROJECT_ROOT / "CHANGELOG.md",
}

# Dashboard files that may contain version metadata
DASHBOARD_FILES = [
    "soil-moisture-main.json",
    "sensor-details.json",
    "alerts-overview.json",
    "mobile-summary.json",
    "rpi-health.json",
    "system-health.json",
]

SEMVER_PATTERN = re.compile(r'^\d+\.\d+\.\d+$')


class Colors:
    """ANSI color codes for terminal output."""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'


def validate_version(version: str) -> bool:
    """Validate semantic version format (X.Y.Z)."""
    return SEMVER_PATTERN.match(version) is not None


def get_current_version() -> str:
    """Extract current version from root README.md."""
    readme_path = VERSION_FILES["root_readme"]
    
    if not readme_path.exists():
        print(f"{Colors.RED}✗ Root README.md not found{Colors.ENDC}")
        return None
    
    content = readme_path.read_text()
    match = re.search(r'# .*— v(\d+\.\d+\.\d+)', content)
    
    if match:
        return match.group(1)
    else:
        print(f"{Colors.YELLOW}⚠ Could not detect version from README.md{Colors.ENDC}")
        return None


def update_root_readme(content: str, old_version: str, new_version: str) -> str:
    """Update version in root README.md title."""
    pattern = rf'(# .*— v){old_version}'
    replacement = rf'\g<1>{new_version}'
    updated = re.sub(pattern, replacement, content)
    
    if updated == content:
        print(f"{Colors.YELLOW}  ⚠ No version found in root README.md title{Colors.ENDC}")
    
    return updated


def update_dashboard_readme(content: str, old_version: str, new_version: str) -> str:
    """Update version in grafana-dashboards/README.md."""
    updates = []
    
    # Update main title version
    pattern1 = rf'(Soil Moisture Monitoring System \(v){old_version}\)'
    if re.search(pattern1, content):
        content = re.sub(pattern1, rf'\g<1>{new_version})', content)
        updates.append("title")
    
    # Update "Last updated" footer
    today = datetime.now().strftime("%Y-%m-%d")
    pattern2 = rf'Last updated: \d{{4}}-\d{{2}}-\d{{2}} \(v{old_version}\)'
    if re.search(pattern2, content):
        content = re.sub(pattern2, f'Last updated: {today} (v{new_version})', content)
        updates.append("footer")
    
    if not updates:
        print(f"{Colors.YELLOW}  ⚠ No version references found in dashboard README{Colors.ENDC}")
    
    return content


def update_changelog(content: str, new_version: str, create_entry: bool = False) -> str:
    """Update CHANGELOG.md with new version entry."""
    if not create_entry:
        return content
    
    today = datetime.now().strftime("%Y-%m-%d")
    
    # Create new version entry template
    new_entry = f"""## [{new_version}] - {today}

### Added

#### New Features
- **Feature 1** — Description here

### Changed

#### Improvements
- **Improvement 1** — Description here

### Fixed

#### Bug Fixes
- **Fix 1** — Description here

---

"""
    
    # Insert after the header section (after "---\n\n")
    header_end = content.find("---\n\n")
    if header_end != -1:
        insert_pos = header_end + len("---\n\n")
        updated = content[:insert_pos] + new_entry + content[insert_pos:]
        return updated
    else:
        print(f"{Colors.YELLOW}  ⚠ Could not find insertion point in CHANGELOG{Colors.ENDC}")
        return content


def update_dashboard_json(filepath: Path, new_version: str) -> bool:
    """Update version metadata in dashboard JSON (if present)."""
    try:
        with open(filepath, 'r') as f:
            dashboard = json.load(f)
        
        # Update version in dashboard description or title if present
        updated = False
        
        # Check if description contains version
        if 'description' in dashboard and re.search(r'v\d+\.\d+\.\d+', dashboard.get('description', '')):
            dashboard['description'] = re.sub(
                r'v\d+\.\d+\.\d+',
                f'v{new_version}',
                dashboard['description']
            )
            updated = True
        
        # Update tags if version tag exists
        if 'tags' in dashboard and isinstance(dashboard['tags'], list):
            new_tags = []
            for tag in dashboard['tags']:
                if re.match(r'v\d+\.\d+\.\d+', tag):
                    new_tags.append(f'v{new_version}')
                    updated = True
                else:
                    new_tags.append(tag)
            if updated:
                dashboard['tags'] = new_tags
        
        if updated:
            with open(filepath, 'w') as f:
                json.dump(dashboard, f, indent=2)
            return True
        
        return False
        
    except Exception as e:
        print(f"{Colors.YELLOW}  ⚠ Error updating {filepath.name}: {e}{Colors.ENDC}")
        return False


def show_diff(filepath: Path, old_content: str, new_content: str):
    """Show diff between old and new content."""
    if old_content == new_content:
        print(f"  {Colors.BLUE}○{Colors.ENDC} No changes")
        return
    
    old_lines = old_content.splitlines()
    new_lines = new_content.splitlines()
    
    print(f"  {Colors.GREEN}✓{Colors.ENDC} Changes detected:")
    
    for i, (old, new) in enumerate(zip(old_lines, new_lines)):
        if old != new:
            print(f"    {Colors.RED}- {old}{Colors.ENDC}")
            print(f"    {Colors.GREEN}+ {new}{Colors.ENDC}")
            break  # Show only first change for brevity


def update_version(new_version: str, create_changelog: bool = False, dry_run: bool = False) -> int:
    """
    Update version across all project files.
    
    Args:
        new_version: New version number (e.g., "2.7.0")
        create_changelog: Whether to create CHANGELOG entry
        dry_run: Show changes without applying them
    
    Returns:
        0 on success, 1 on error
    """
    print(f"\n{Colors.HEADER}{'='*60}{Colors.ENDC}")
    print(f"{Colors.HEADER}Version Update Script - Soil Moisture Monitoring System{Colors.ENDC}")
    print(f"{Colors.HEADER}{'='*60}{Colors.ENDC}\n")
    
    # Validate version format
    if not validate_version(new_version):
        print(f"{Colors.RED}✗ Invalid version format: {new_version}{Colors.ENDC}")
        print(f"  Expected format: X.Y.Z (e.g., 2.7.0)")
        return 1
    
    # Get current version
    current_version = get_current_version()
    if not current_version:
        print(f"{Colors.RED}✗ Could not detect current version{Colors.ENDC}")
        return 1
    
    print(f"{Colors.CYAN}Current version: {Colors.BOLD}v{current_version}{Colors.ENDC}")
    print(f"{Colors.CYAN}New version:     {Colors.BOLD}v{new_version}{Colors.ENDC}")
    print(f"{Colors.CYAN}Mode:            {Colors.BOLD}{'DRY RUN' if dry_run else 'APPLY CHANGES'}{Colors.ENDC}\n")
    
    if current_version == new_version:
        print(f"{Colors.YELLOW}⚠ Version unchanged ({new_version}){Colors.ENDC}")
        return 1
    
    files_updated = []
    
    # Update root README.md
    print(f"{Colors.BOLD}1. Updating root README.md{Colors.ENDC}")
    readme_path = VERSION_FILES["root_readme"]
    if readme_path.exists():
        old_content = readme_path.read_text()
        new_content = update_root_readme(old_content, current_version, new_version)
        show_diff(readme_path, old_content, new_content)
        
        if not dry_run and old_content != new_content:
            readme_path.write_text(new_content)
            files_updated.append("README.md")
    else:
        print(f"  {Colors.RED}✗ File not found{Colors.ENDC}")
    
    # Update grafana-dashboards/README.md
    print(f"\n{Colors.BOLD}2. Updating grafana-dashboards/README.md{Colors.ENDC}")
    dashboard_readme_path = VERSION_FILES["dashboard_readme"]
    if dashboard_readme_path.exists():
        old_content = dashboard_readme_path.read_text()
        new_content = update_dashboard_readme(old_content, current_version, new_version)
        show_diff(dashboard_readme_path, old_content, new_content)
        
        if not dry_run and old_content != new_content:
            dashboard_readme_path.write_text(new_content)
            files_updated.append("grafana-dashboards/README.md")
    else:
        print(f"  {Colors.RED}✗ File not found{Colors.ENDC}")
    
    # Update CHANGELOG.md
    print(f"\n{Colors.BOLD}3. Updating CHANGELOG.md{Colors.ENDC}")
    changelog_path = VERSION_FILES["changelog"]
    if changelog_path.exists():
        old_content = changelog_path.read_text()
        new_content = update_changelog(old_content, new_version, create_changelog)
        
        if create_changelog:
            show_diff(changelog_path, old_content, new_content)
            if not dry_run and old_content != new_content:
                changelog_path.write_text(new_content)
                files_updated.append("CHANGELOG.md")
        else:
            print(f"  {Colors.BLUE}○{Colors.ENDC} Skipped (use --changelog to create entry)")
    else:
        print(f"  {Colors.RED}✗ File not found{Colors.ENDC}")
    
    # Update dashboard JSON files
    print(f"\n{Colors.BOLD}4. Updating dashboard JSON files{Colors.ENDC}")
    dashboards_dir = PROJECT_ROOT / "grafana-dashboards"
    dashboard_updates = 0
    
    for dashboard_file in DASHBOARD_FILES:
        filepath = dashboards_dir / dashboard_file
        if filepath.exists():
            if not dry_run:
                if update_dashboard_json(filepath, new_version):
                    print(f"  {Colors.GREEN}✓{Colors.ENDC} {dashboard_file}")
                    files_updated.append(f"grafana-dashboards/{dashboard_file}")
                    dashboard_updates += 1
                else:
                    print(f"  {Colors.BLUE}○{Colors.ENDC} {dashboard_file} (no version metadata)")
            else:
                print(f"  {Colors.BLUE}○{Colors.ENDC} {dashboard_file} (would check)")
    
    if dashboard_updates == 0:
        print(f"  {Colors.BLUE}ℹ{Colors.ENDC}  No dashboards contain version metadata")
    
    # Summary
    print(f"\n{Colors.HEADER}{'='*60}{Colors.ENDC}")
    if dry_run:
        print(f"{Colors.CYAN}DRY RUN COMPLETE - No files were modified{Colors.ENDC}")
    else:
        print(f"{Colors.GREEN}✓ Version update complete!{Colors.ENDC}")
        print(f"{Colors.GREEN}  Updated {len(files_updated)} file(s){Colors.ENDC}")
    
    print(f"\n{Colors.BOLD}Next steps:{Colors.ENDC}")
    if not create_changelog:
        print(f"  1. Edit CHANGELOG.md manually (or re-run with --changelog)")
    else:
        print(f"  1. Fill in CHANGELOG.md entry for v{new_version}")
    print(f"  2. Review changes: {Colors.CYAN}git diff{Colors.ENDC}")
    print(f"  3. Commit: {Colors.CYAN}git add -A && git commit -m 'chore: bump version to v{new_version}'{Colors.ENDC}")
    print(f"  4. Create PR or merge to main")
    print(f"{Colors.HEADER}{'='*60}{Colors.ENDC}\n")
    
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Update version numbers across the Soil Moisture Monitoring System project",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s 2.7.0                    # Bump version to 2.7.0
  %(prog)s 2.7.0 --changelog        # Bump version + create CHANGELOG entry
  %(prog)s --current                # Show current version
  %(prog)s 2.7.0 --dry-run          # Preview changes without applying
        """
    )
    
    parser.add_argument(
        'version',
        nargs='?',
        help='New version number (e.g., 2.7.0)'
    )
    
    parser.add_argument(
        '--current',
        action='store_true',
        help='Show current version and exit'
    )
    
    parser.add_argument(
        '--changelog',
        action='store_true',
        help='Create CHANGELOG.md entry template'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Preview changes without modifying files'
    )
    
    args = parser.parse_args()
    
    # Show current version
    if args.current:
        current = get_current_version()
        if current:
            print(f"Current version: v{current}")
            return 0
        else:
            return 1
    
    # Require version argument
    if not args.version:
        parser.print_help()
        return 1
    
    # Run version update
    return update_version(args.version, args.changelog, args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
