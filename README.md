# Squid Caching Proxy for Docker Builds

A caching HTTP/HTTPS proxy that speeds up `docker compose build` by caching package downloads from apt, npm, pip, Go modules, and any other HTTP/HTTPS traffic.

Runs as a Docker container. Other machines on the network can use it too.

## Quick Start

```bash
# 1. Generate the CA certificate (one-time)
./scripts/generate-ca.sh

# 2. Copy environment config
cp .env.example .env

# 3. Start the proxy
docker compose up -d

# 4. Verify it's running
docker compose logs -f
```

The proxy is now running on port **3128**.

## Configure Docker Builds to Use the Proxy

There are two parts: (1) tell Docker to route traffic through the proxy, and (2) trust the CA certificate inside your Dockerfiles.

### Option A: Docker daemon proxy (applies to all builds automatically)

Create or edit `/etc/systemd/system/docker.service.d/proxy.conf`:

```ini
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:3128"
Environment="HTTPS_PROXY=http://127.0.0.1:3128"
Environment="NO_PROXY=localhost,127.0.0.1"
```

Then reload:

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
```

> **Note:** This routes all Docker daemon traffic (pulls, builds) through the proxy. If you only want builds proxied, use Option B instead.

### Option B: Per-build with build args

Pass proxy settings as build args:

```bash
docker compose build \
  --build-arg http_proxy=http://HOST_IP:3128 \
  --build-arg https_proxy=http://HOST_IP:3128 \
  --build-arg HTTP_PROXY=http://HOST_IP:3128 \
  --build-arg HTTPS_PROXY=http://HOST_IP:3128
```

Or in `docker-compose.yml`:

```yaml
services:
  myapp:
    build:
      context: .
      args:
        http_proxy: http://HOST_IP:3128
        https_proxy: http://HOST_IP:3128
```

Replace `HOST_IP` with your machine's LAN IP (not `localhost` — Docker build runs in an isolated network).

Find your IP: `hostname -I | awk '{print $1}'`

### Option C: Docker client config (applies to all containers)

Edit `~/.docker/config.json`:

```json
{
  "proxies": {
    "default": {
      "httpProxy": "http://HOST_IP:3128",
      "httpsProxy": "http://HOST_IP:3128",
      "noProxy": "localhost,127.0.0.1"
    }
  }
}
```

## Trust the CA Certificate in Dockerfiles

Since the proxy intercepts HTTPS (SSL bump), containers need to trust the proxy's CA certificate. Add these lines to your Dockerfiles.

### Debian / Ubuntu

```dockerfile
COPY path/to/proxy/certs/ca.pem /usr/local/share/ca-certificates/squid-ca.crt
RUN update-ca-certificates

# For npm (uses its own CA store)
ENV NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/squid-ca.crt

# For pip (uses requests library CA bundle)
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt
```

### Alpine

```dockerfile
COPY path/to/proxy/certs/ca.pem /usr/local/share/ca-certificates/squid-ca.crt
RUN update-ca-certificates

ENV NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/squid-ca.crt
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt
```

### RHEL / Fedora / CentOS

```dockerfile
COPY path/to/proxy/certs/ca.pem /etc/pki/ca-trust/source/anchors/squid-ca.pem
RUN update-ca-trust

ENV NODE_EXTRA_CA_CERTS=/etc/pki/ca-trust/source/anchors/squid-ca.pem
ENV REQUESTS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt
ENV PIP_CERT=/etc/pki/tls/certs/ca-bundle.crt
```

### Go

Go respects the system CA store after `update-ca-certificates`, so no extra env var is needed. If you need it explicitly:

```dockerfile
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
```

## Configure Other Machines on the Network

Other machines can use this proxy by setting environment variables pointing to your host's IP.

### Linux (bash)

```bash
export http_proxy=http://PROXY_HOST_IP:3128
export https_proxy=http://PROXY_HOST_IP:3128
export HTTP_PROXY=http://PROXY_HOST_IP:3128
export HTTPS_PROXY=http://PROXY_HOST_IP:3128
```

Add to `~/.bashrc` or `/etc/environment` to persist.

The remote machine also needs to trust the CA certificate:

```bash
# Fedora/RHEL
sudo cp ca.pem /etc/pki/ca-trust/source/anchors/squid-proxy-ca.pem
sudo update-ca-trust

# Debian/Ubuntu
sudo cp ca.pem /usr/local/share/ca-certificates/squid-proxy-ca.crt
sudo update-ca-certificates
```

Copy `certs/ca.pem` from this repo to the remote machine.

### Docker on remote machines

Same Docker daemon proxy config as above, but use the proxy host's LAN IP instead of `127.0.0.1`.

## Configure Fedora Host System Proxy (Optional)

If you want your host system (not just Docker) to use the proxy:

```bash
# Trust the CA cert
sudo cp certs/ca.pem /etc/pki/ca-trust/source/anchors/squid-proxy-ca.pem
sudo update-ca-trust

# Set system-wide proxy
sudo tee /etc/profile.d/proxy.sh << 'EOF'
export http_proxy=http://127.0.0.1:3128
export https_proxy=http://127.0.0.1:3128
export HTTP_PROXY=http://127.0.0.1:3128
export HTTPS_PROXY=http://127.0.0.1:3128
export no_proxy=localhost,127.0.0.1
EOF
```

Log out and back in, or `source /etc/profile.d/proxy.sh`.

## Storage Management

### Check cache usage

```bash
./scripts/check-storage.sh
```

Shows disk usage and Squid cache manager statistics (hit/miss ratios, storage details).

### Clean all cached data

```bash
./scripts/clean-cache.sh
```

Stops the proxy, removes all cached data, and restarts.

### View live access log

```bash
docker compose logs -f squid
```

## Configuration

Edit `.env` to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `PROXY_PORT` | `3128` | Port exposed on the host |

Cache size and retention are configured in `squid.conf`:

| Setting | Default | Line to edit |
|---------|---------|-------------|
| Cache size | 100 GB | `cache_dir rock /var/spool/squid 102400` (value in MB) |
| Max object size | 1 GB | `maximum_object_size 1 GB` |
| RAM cache | 512 MB | `cache_mem 512 MB` |
| Default retention | 365 days | `refresh_pattern` lines (value in minutes: 525600 = 365 days) |

## Firewall

If other machines need to reach the proxy, open port 3128:

```bash
sudo firewall-cmd --add-port=3128/tcp --permanent
sudo firewall-cmd --reload
```

## Troubleshooting

### "certificate verify failed" errors

The CA cert is not trusted in the build container. Make sure your Dockerfile copies and trusts `ca.pem` (see above).

### Cache misses for everything

Check that the proxy env vars are actually being used inside the build:

```dockerfile
RUN echo "Proxy: $http_proxy" && curl -v https://example.com
```

### Squid won't start

Check logs:

```bash
docker compose logs squid
```

Common issues:
- Missing CA cert: run `./scripts/generate-ca.sh` first
- Port 3128 in use: change `PROXY_PORT` in `.env`
- Cache dir permissions: the entrypoint handles this, but if you see permission errors, try `sudo chown -R 13:13 cache_dir/`

### Build arg proxy not working

Some base images don't pass build args to all stages. In multi-stage builds, re-declare the args:

```dockerfile
FROM node:20 AS builder
ARG http_proxy
ARG https_proxy
# ... rest of build
```
