#!/usr/bin/env bash
# install-influx-cli.sh — put the `influx` CLI on the host.
#
# InfluxDB runs in Docker here, so the CLI is absent from the host and
# sensor-backup.sh silently did nothing for three months. The binary is lifted
# straight out of the InfluxDB image so its version always matches the running
# server, and so this never depends on InfluxData's APT repo (which fails GPG
# verification on Debian Trixie — see RECOVERY.md).
#
#   sudo bash install-influx-cli.sh

set -euo pipefail
IMAGE="${INFLUX_IMAGE:-influxdb:2.7.12}"
DEST=/usr/local/bin/influx

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }

if command -v influx >/dev/null 2>&1; then
    echo "influx CLI already present: $(influx version 2>&1 | head -1)"
    exit 0
fi

echo "Extracting the influx CLI from $IMAGE ..."
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"

CID=$(docker create "$IMAGE")
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT

if docker cp "$CID:/usr/local/bin/influx" "$DEST" 2>/dev/null; then
    chmod +x "$DEST"
    echo "Installed: $("$DEST" version 2>&1 | head -1)"
else
    echo "!! The image does not ship the CLI at /usr/local/bin/influx."
    echo "   Fall back to the standalone client:"
    echo "   https://docs.influxdata.com/influxdb/v2/tools/influx-cli/"
    exit 1
fi
