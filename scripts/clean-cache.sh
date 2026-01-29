#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="${PROJECT_DIR}/cache_dir"

echo "=== Clean Squid Cache ==="
echo ""

if [ ! -d "${CACHE_DIR}" ]; then
    echo "Cache directory not found. Nothing to clean."
    exit 0
fi

echo "Current cache usage:"
du -sh "${CACHE_DIR}" 2>/dev/null || echo "  (unable to read)"
echo ""

read -p "This will stop the proxy, delete all cached data, and restart. Continue? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Stopping proxy..."
docker compose -f "${PROJECT_DIR}/docker-compose.yml" down 2>/dev/null || true

echo "Removing cache data..."
rm -rf "${CACHE_DIR:?}"/*

echo "Starting proxy..."
docker compose -f "${PROJECT_DIR}/docker-compose.yml" up -d

echo ""
echo "Cache cleaned and proxy restarted."
