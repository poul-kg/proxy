#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="${PROJECT_DIR}/cache_dir"

echo "=== Cache Storage Usage ==="
echo ""

if [ -d "${CACHE_DIR}" ]; then
    echo "Disk usage:"
    du -sh "${CACHE_DIR}" 2>/dev/null || echo "  (unable to read — may need sudo)"
    echo ""
    du -sh "${CACHE_DIR}"/* 2>/dev/null || true
else
    echo "Cache directory not found at ${CACHE_DIR}"
    echo "Start the proxy first: docker compose up -d"
    exit 1
fi

echo ""
echo "=== Squid Cache Manager Stats ==="
echo ""

if docker compose -f "${PROJECT_DIR}/docker-compose.yml" ps --status running 2>/dev/null | grep -q squid; then
    docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec squid squidclient -h localhost -p 3128 mgr:storedir 2>/dev/null || \
        echo "(Could not reach squid cache manager)"
    echo ""
    echo "=== Cache Hit/Miss Stats ==="
    echo ""
    docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec squid squidclient -h localhost -p 3128 mgr:info 2>/dev/null | \
        grep -E "(Hits|Misses|Storage Swap|Memory)" || \
        echo "(Could not reach squid cache manager)"
else
    echo "(Squid is not running — start with: docker compose up -d)"
fi
