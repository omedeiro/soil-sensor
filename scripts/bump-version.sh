#!/bin/bash
# Version Bump Script for Soil Sensor Project
# Usage: ./scripts/bump-version.sh <major|minor|patch> [firmware|system|docs]
#
# Examples:
#   ./scripts/bump-version.sh minor system  # System/infrastructure update (2.4.0 → 2.5.0)
#   ./scripts/bump-version.sh minor firmware # Firmware update (2.2.0 → 2.3.0)
#   ./scripts/bump-version.sh patch docs     # Documentation update (2.5.0 → 2.5.1)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to project root
cd "$PROJECT_ROOT"

# Function to print colored output
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Function to increment version
increment_version() {
    local version=$1
    local bump_type=$2
    
    IFS='.' read -r major minor patch <<< "$version"
    
    case $bump_type in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            print_error "Invalid bump type: $bump_type (use major, minor, or patch)"
            exit 1
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Function to get current version from CHANGELOG
get_current_version() {
    grep -m 1 "^## \[" docs/CHANGELOG.md | sed -E 's/## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/'
}

# Function to get current firmware version
get_firmware_version() {
    grep "FIRMWARE_VERSION" firmware/src/config.h | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/'
}

# Function to update file with sed
update_file() {
    local file=$1
    local pattern=$2
    local replacement=$3
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS requires empty string after -i
        sed -i '' "s|$pattern|$replacement|g" "$file"
    else
        # Linux
        sed -i "s|$pattern|$replacement|g" "$file"
    fi
    
    print_success "Updated $file"
}

# Validate arguments
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    print_error "Usage: $0 <major|minor|patch> [firmware|system|docs]"
    exit 1
fi

BUMP_TYPE=$1
UPDATE_TYPE=${2:-system}  # Default to system update

# Get current versions
CURRENT_VERSION=$(get_current_version)
CURRENT_FIRMWARE_VERSION=$(get_firmware_version)
CURRENT_DATE=$(date +%Y-%m-%d)

print_info "Current system version: $CURRENT_VERSION"
print_info "Current firmware version: $CURRENT_FIRMWARE_VERSION"
print_info "Update type: $UPDATE_TYPE"

# Calculate new version
case $UPDATE_TYPE in
    system|docs)
        NEW_VERSION=$(increment_version "$CURRENT_VERSION" "$BUMP_TYPE")
        NEW_FIRMWARE_VERSION="$CURRENT_FIRMWARE_VERSION"  # Keep firmware version same
        ;;
    firmware)
        NEW_VERSION=$(increment_version "$CURRENT_VERSION" "$BUMP_TYPE")
        NEW_FIRMWARE_VERSION=$(increment_version "$CURRENT_FIRMWARE_VERSION" "$BUMP_TYPE")
        ;;
    *)
        print_error "Invalid update type: $UPDATE_TYPE (use firmware, system, or docs)"
        exit 1
        ;;
esac

print_info "New system version: $NEW_VERSION"
print_info "New firmware version: $NEW_FIRMWARE_VERSION"

# Confirm with user
echo ""
read -p "$(echo -e ${YELLOW}Continue with version bump?${NC} [y/N] )" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Version bump cancelled"
    exit 0
fi

echo ""
print_info "Updating version references..."

# 1. Update CHANGELOG.md (add new version entry at top)
print_info "Updating CHANGELOG.md..."
CHANGELOG_ENTRY="---\n\n## [$NEW_VERSION] - $CURRENT_DATE\n\n### Changed\n\n#### TODO: Add changes here\n\n---\n\n## [$CURRENT_VERSION]"
update_file "docs/CHANGELOG.md" "---\n\n## \[$CURRENT_VERSION\]" "$CHANGELOG_ENTRY"

# 2. Update README.md (main version header)
print_info "Updating README.md..."
update_file "README.md" "# 🌱 Soil Moisture Monitoring System — v[0-9]*\.[0-9]*\.[0-9]*" "# 🌱 Soil Moisture Monitoring System — v$NEW_VERSION"

# 3. Update firmware version if firmware update
if [ "$UPDATE_TYPE" == "firmware" ]; then
    print_info "Updating firmware version in config.h..."
    update_file "firmware/src/config.h" "#define FIRMWARE_VERSION \"[0-9]*\.[0-9]*\.[0-9]*\"" "#define FIRMWARE_VERSION \"$NEW_FIRMWARE_VERSION\""
    
    # Update README.md firmware version reference
    update_file "README.md" "### ESP8266 Firmware (v[0-9]*\.[0-9]*\.[0-9]*)" "### ESP8266 Firmware (v$NEW_FIRMWARE_VERSION)"
fi

# 4. Update README.md Raspberry Pi version if system update
if [ "$UPDATE_TYPE" == "system" ]; then
    print_info "Updating Raspberry Pi version in README.md..."
    update_file "README.md" "### Raspberry Pi Server (v[0-9]*\.[0-9]*\.[0-9]*)" "### Raspberry Pi Server (v$NEW_VERSION)"
fi

# 5. Update grafana-dashboards/README.md if system update
if [ "$UPDATE_TYPE" == "system" ] || [ "$UPDATE_TYPE" == "firmware" ]; then
    print_info "Updating grafana-dashboards/README.md..."
    update_file "grafana-dashboards/README.md" "6 production-ready dashboards for the Soil Moisture Monitoring System (v[0-9]*\.[0-9]*\.[0-9]*)" "6 production-ready dashboards for the Soil Moisture Monitoring System (v$NEW_VERSION)"
fi

echo ""
print_success "Version bump complete! 🎉"
echo ""
print_info "Updated files:"
echo "  - CHANGELOG.md (added v$NEW_VERSION entry)"
echo "  - README.md (main version → v$NEW_VERSION)"
if [ "$UPDATE_TYPE" == "firmware" ]; then
    echo "  - firmware/src/config.h (firmware version → v$NEW_FIRMWARE_VERSION)"
    echo "  - README.md (firmware version → v$NEW_FIRMWARE_VERSION)"
fi
if [ "$UPDATE_TYPE" == "system" ]; then
    echo "  - README.md (Raspberry Pi version → v$NEW_VERSION)"
    echo "  - grafana-dashboards/README.md (version → v$NEW_VERSION)"
fi

echo ""
print_warning "Next steps:"
echo "  1. Edit CHANGELOG.md and replace 'TODO: Add changes here' with actual changes"
echo "  2. Review all changes: git diff"
echo "  3. Commit changes: git add . && git commit -m 'chore: bump version to v$NEW_VERSION'"
echo "  4. Create PR: gh pr create --title 'Release v$NEW_VERSION' --body '...'"
echo "  5. After merge, tag release: git tag -a v$NEW_VERSION -m 'Release v$NEW_VERSION' && git push origin v$NEW_VERSION"
