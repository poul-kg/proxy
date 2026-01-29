#!/bin/bash
set -e

CERT_DIR="/etc/squid/certs"
CACHE_DIR="/var/spool/squid"
SSL_DB="${CACHE_DIR}/ssl_db"

# Remove stale PID file from previous crashes
rm -f /run/squid.pid

# Verify CA certificate exists
if [ ! -f "${CERT_DIR}/ca.pem" ] || [ ! -f "${CERT_DIR}/ca.key" ]; then
    echo "ERROR: CA certificate not found at ${CERT_DIR}/ca.pem and ${CERT_DIR}/ca.key"
    echo "Run ./scripts/generate-ca.sh first"
    exit 1
fi

# Initialize SSL certificate database
if [ ! -d "${SSL_DB}" ]; then
    echo "Initializing SSL certificate database..."
    /usr/lib/squid/security_file_certgen -c -s "${SSL_DB}" -M 16MB
    chown -R proxy:proxy "${SSL_DB}"
fi

# Fix permissions
chown -R proxy:proxy "${CACHE_DIR}"

# Initialize cache directory if needed (creates swap directories)
if [ ! -d "${CACHE_DIR}/00" ]; then
    echo "Initializing cache directory..."
    squid -z -N 2>&1
    rm -f /run/squid.pid
fi

echo "Starting Squid proxy..."
exec squid -NYC -d 1
