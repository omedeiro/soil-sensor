# Branch Protection and Release Workflow

This document explains how to protect the `main` branch and follow proper release workflows.

---

## 🔒 Protecting the Main Branch

### Why Protect Main?

Branch protection prevents:
- Direct pushes to `main` (forces PR workflow)
- Merging broken code (requires passing checks)
- Accidental deletions
- Force pushes that rewrite history

### Setup via GitHub Web UI

1. **Navigate to Repository Settings**
   ```
   https://github.com/omedeiro/soil-sensor/settings/branches
   ```

2. **Add Branch Protection Rule**
   - Click "Add branch protection rule"
   - Branch name pattern: `main`

3. **Recommended Settings**

   #### ✅ Basic Protection
   - [x] **Require a pull request before merging**
     - [x] Require approvals: 1 (or 0 if you're the only maintainer)
     - [ ] Dismiss stale pull request approvals when new commits are pushed (optional)
     - [x] Require review from Code Owners (if you have CODEOWNERS file)
   
   #### ✅ Status Checks (if you have CI/CD)
   - [ ] Require status checks to pass before merging
     - [ ] Require branches to be up to date before merging
   
   #### ✅ Additional Restrictions
   - [x] **Require conversation resolution before merging**
   - [x] **Include administrators** (applies rules to admins too)
   - [ ] Restrict who can push to matching branches (optional, for teams)
   
   #### ✅ Force Push Protection
   - [x] **Do not allow bypassing the above settings**
   - [x] **Do not allow force pushes**
   - [x] **Do not allow deletions**

4. **Save Changes**
   - Click "Create" or "Save changes"

### Setup via GitHub CLI (Alternative)

```bash
# Install GitHub CLI if not already installed
# macOS: brew install gh
# Login: gh auth login

# Enable branch protection for main
gh api repos/omedeiro/soil-sensor/branches/main/protection \
  --method PUT \
  --field required_pull_request_reviews[required_approving_review_count]=0 \
  --field required_pull_request_reviews[dismiss_stale_reviews]=false \
  --field enforce_admins=true \
  --field required_conversation_resolution=true \
  --field allow_force_pushes=false \
  --field allow_deletions=false
```

### Verify Protection

```bash
# Check branch protection status
gh api repos/omedeiro/soil-sensor/branches/main/protection

# Or visit:
# https://github.com/omedeiro/soil-sensor/settings/branches
```

---

## 🚀 Release Workflow

### 1. Create Feature Branch

```bash
# Create branch for your changes
git checkout -b feature/my-feature

# Make your changes...
# Commit changes...
git add .
git commit -m "feat: add new feature"
```

### 2. Bump Version (if releasing)

```bash
# Use the automated version bump script
./scripts/bump-version.sh <major|minor|patch> [firmware|system|docs]

# Examples:
./scripts/bump-version.sh minor system   # System update (2.5.0 → 2.6.0)
./scripts/bump-version.sh minor firmware # Firmware update (2.2.0 → 2.3.0)
./scripts/bump-version.sh patch docs     # Docs update (2.5.0 → 2.5.1)
```

**What the script updates:**
- ✅ `CHANGELOG.md` — Adds new version entry
- ✅ `README.md` — Updates main version header
- ✅ `firmware/src/config.h` — Updates firmware version (if firmware bump)
- ✅ `grafana-dashboards/README.md` — Updates dashboard suite version

**Manual steps after script:**
1. Edit `CHANGELOG.md` — Replace "TODO: Add changes here" with actual changes
2. Review changes — `git diff`
3. Commit version bump — `git add . && git commit -m "chore: bump version to vX.Y.Z"`

### 3. Push Branch and Create PR

```bash
# Push branch to remote
git push -u origin feature/my-feature

# Create PR using GitHub CLI
gh pr create \
  --title "Release vX.Y.Z: Brief description" \
  --body "$(cat <<'EOF'
## Summary
Brief description of changes

### Changes
- Change 1
- Change 2

### Testing
- [ ] Tested locally
- [ ] Firmware flashed successfully
- [ ] InfluxDB receiving data
- [ ] Grafana dashboards updated
EOF
)"
```

### 4. Review and Merge PR

```bash
# View PR in browser
gh pr view --web

# After review, merge PR (requires approval if configured)
gh pr merge --squash  # or --merge or --rebase
```

### 5. Tag Release (After Merge)

```bash
# Switch to main branch and pull
git checkout main
git pull origin main

# Create annotated tag
git tag -a v2.5.0 -m "Release v2.5.0: Description"

# Push tag to remote
git push origin v2.5.0

# Create GitHub release
gh release create v2.5.0 \
  --title "Release v2.5.0" \
  --notes "$(cat CHANGELOG.md | sed -n '/## \[2.5.0\]/,/## \[2.4.0\]/p' | head -n -2)"
```

---

## 📋 Version Bump Checklist

### Files Updated by Script
- [x] `CHANGELOG.md` — New version entry added
- [x] `README.md` — Main version header updated
- [x] `firmware/src/config.h` — Firmware version updated (if firmware bump)
- [x] `grafana-dashboards/README.md` — Dashboard suite version updated

### Files to Review Manually (if changed)
- [ ] `grafana-dashboards/soil-moisture-main.json` — Increment `"version"` field if dashboard changed
- [ ] `grafana-dashboards/mobile-summary.json` — Increment `"version"` if changed
- [ ] `grafana-dashboards/system-health.json` — Increment `"version"` if changed
- [ ] `grafana-dashboards/sensor-details.json` — Increment `"version"` if changed
- [ ] `grafana-dashboards/rpi-health.json` — Increment `"version"` if changed
- [ ] `grafana-dashboards/alerts-overview.json` — Increment `"version"` if changed
- [ ] `docs/DIAGNOSTICS_REFERENCE.md` — Update version header if diagnostics changed
- [ ] `docs/UPGRADE_PROCEDURE.md` — Update version if upgrade steps changed
- [ ] `rpi-setup/README.md` — Update InfluxDB/Grafana versions if infrastructure changed

---

## 🔄 Hotfix Workflow (Emergency Fixes)

If you need to bypass normal workflow for critical bugs:

### Option 1: Temporary Branch Protection Bypass (Admins Only)

1. Go to Settings → Branches
2. Temporarily disable "Include administrators"
3. Make direct push to `main`
4. **IMMEDIATELY re-enable protection**

### Option 2: Fast-Track PR (Recommended)

```bash
# Create hotfix branch
git checkout -b hotfix/critical-bug

# Make fix
git add .
git commit -m "fix: critical bug"

# Push and create PR
git push -u origin hotfix/critical-bug
gh pr create --title "Hotfix: Critical bug" --body "Emergency fix for..."

# Merge immediately (bypass review if necessary)
gh pr merge --admin --squash
```

---

## 📊 Version Numbering Strategy

Following [Semantic Versioning](https://semver.org/):

### MAJOR.MINOR.PATCH (e.g., 2.5.1)

- **MAJOR (2.x.x)** — Breaking changes, incompatible API changes
  - Example: Complete rewrite of InfluxDB integration
  - Example: Firmware protocol changes requiring Raspberry Pi updates
  
- **MINOR (x.5.x)** — New features, backwards-compatible
  - Example: Adding new sensor support
  - Example: New Grafana dashboard
  - Example: WiFi stability improvements
  
- **PATCH (x.x.1)** — Bug fixes, documentation updates
  - Example: Fixing typo in README
  - Example: Dashboard label corrections
  - Example: Serial output formatting

### Firmware vs System Versioning

- **Firmware version** (`firmware/src/config.h`) — ESP8266 code version
- **System version** (`README.md`, `CHANGELOG.md`) — Overall project version

These can diverge:
- System v2.5.0 + Firmware v2.2.0 = Grafana/docs updates only
- System v2.6.0 + Firmware v2.3.0 = Firmware update

---

## 🛠️ Troubleshooting

### "Protected branch update failed"

You tried to push directly to `main`. Use PR workflow:

```bash
# Create feature branch
git checkout -b feature/my-fix

# Push and create PR
git push -u origin feature/my-fix
gh pr create
```

### "Required status checks failed"

If you have CI/CD configured, wait for checks to pass before merging.

### "Need approval before merging"

Ask another maintainer to review your PR, or temporarily adjust protection settings.

---

## 📚 References

- [GitHub Branch Protection Docs](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [Semantic Versioning](https://semver.org/)
- [Keep a Changelog](https://keepachangelog.com/)
- [GitHub CLI Docs](https://cli.github.com/manual/)
