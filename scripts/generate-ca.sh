#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CERT_DIR="${PROJECT_DIR}/certs"

mkdir -p "${CERT_DIR}"

if [ -f "${CERT_DIR}/ca.pem" ] && [ -f "${CERT_DIR}/ca.key" ]; then
    echo "CA certificate already exists at ${CERT_DIR}/ca.pem"
    echo "To regenerate, remove the certs/ directory first."
    exit 0
fi

echo "Generating CA certificate..."
openssl req -new -newkey rsa:4096 -sha256 -days 3650 -nodes -x509 \
    -config "${PROJECT_DIR}/openssl.conf" \
    -keyout "${CERT_DIR}/ca.key" \
    -out "${CERT_DIR}/ca.pem"

chmod 644 "${CERT_DIR}/ca.pem"
chmod 600 "${CERT_DIR}/ca.key"

echo ""
echo "CA certificate generated:"
echo "  Certificate: ${CERT_DIR}/ca.pem"
echo "  Private key: ${CERT_DIR}/ca.key"
echo ""
echo "=== Next steps ==="
echo ""
echo "1. Start the proxy:"
echo "   docker compose up -d"
echo ""
echo "2. To trust this CA on your Fedora host (optional, for non-Docker use):"
echo "   sudo cp ${CERT_DIR}/ca.pem /etc/pki/ca-trust/source/anchors/squid-proxy-ca.pem"
echo "   sudo update-ca-trust"
echo ""
echo "3. Add to your Dockerfiles (see README.md for full examples):"
echo "   COPY certs/ca.pem /usr/local/share/ca-certificates/squid-ca.crt"
echo "   RUN update-ca-certificates"
