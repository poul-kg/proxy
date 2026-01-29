# Squid Caching Proxy for Docker Builds

A caching HTTP/HTTPS proxy that speeds up `docker compose build` by caching package downloads from apt, npm, pip, Go modules, and any other HTTP/HTTPS traffic.

Runs as a Docker container. Other machines on the network can use it too.

## Quick Start

```bash
# 1. Generate the CA certificate (one-time)
./scripts/generate-ca.sh

# 2. Copy environment config
cp .env.example .env

# 3. Build and start the proxy (BEFORE configuring any Docker/system proxy)
docker compose up -d --build

# 4. Verify it's running
docker compose logs -f
```

The proxy is now running on port **3128**.

> **Important: build order.** You must build and start this proxy container
> **before** configuring the Docker daemon proxy or system-wide proxy (steps
> below). Otherwise Docker would try to route the proxy's own build through
> a proxy that doesn't exist yet.

## Configure Docker Builds to Use the Proxy

There are two parts: (1) tell Docker to route traffic through the proxy, and (2) trust the CA certificate inside your Dockerfiles.

### Option A: Docker daemon proxy (applies to all builds automatically)

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
```

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

> **Chicken-and-egg warning:** With this config active, rebuilding the proxy
> image itself (`docker compose build` in this repo) will fail if the proxy
> isn't running — Docker will try to pull `ubuntu:24.04` through a proxy that
> doesn't exist yet. Two ways to handle this:
>
> 1. **Ensure the proxy is running first.** Run `docker compose up -d` (from
>    the already-built image) before rebuilding.
> 2. **Temporarily bypass the proxy** when rebuilding this repo:
>    ```bash
>    sudo systemctl set-environment HTTP_PROXY="" HTTPS_PROXY=""
>    docker compose up -d --build
>    sudo systemctl set-environment HTTP_PROXY="http://127.0.0.1:3128" HTTPS_PROXY="http://127.0.0.1:3128"
>    ```

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

## Testing the Proxy

After starting the proxy, verify it works:

```bash
# Test HTTPS proxying (host must trust the CA cert)
curl -x http://localhost:3128 https://registry.npmjs.org/
curl -x http://localhost:3128 https://pypi.org/simple/
curl -x http://localhost:3128 https://deb.debian.org/debian/dists/bookworm/Release

# Test HTTP proxying
curl -x http://localhost:3128 http://example.com

# If CA is NOT in system trust store yet, use --cacert
curl -x http://localhost:3128 --cacert ./certs/ca.pem https://registry.npmjs.org/

# Test Docker pull goes through proxy (daemon proxy must be configured)
docker pull alpine:latest

# Check squid logs — look for TCP_MISS (first request) or TCP_HIT (cached)
docker compose logs --tail=30 squid
```

Run the same `curl` command twice — the second time should show `TCP_HIT` in the squid logs.

## macOS Setup

For Macs on the network that should use this proxy. Replace `PROXY_HOST_IP` with the Fedora machine's LAN IP throughout.

### 1. Copy the CA certificate to the Mac

From the proxy host:

```bash
scp certs/ca.pem your-mac:~/ca.pem
```

### 2. Trust the CA certificate (system-wide)

This makes browsers (Chrome, Safari, Firefox), curl, and most apps trust the proxy's HTTPS interception.

**Via terminal:**

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/ca.pem
```

**Via UI:**
1. Double-click `ca.pem` to open in Keychain Access
2. It appears in the "login" keychain — drag it to **System**
3. Double-click the certificate → expand **Trust** → set **When using this certificate** to **Always Trust**
4. Close and enter your password

Restart your browser after this.

### 3. Configure system-wide proxy (terminal)

Add to `~/.zshrc` (or `~/.bashrc`):

```bash
export http_proxy=http://PROXY_HOST_IP:3128
export https_proxy=http://PROXY_HOST_IP:3128
export HTTP_PROXY=http://PROXY_HOST_IP:3128
export HTTPS_PROXY=http://PROXY_HOST_IP:3128
export no_proxy=localhost,127.0.0.1
```

Then `source ~/.zshrc` or open a new terminal.

### 4. Configure macOS system proxy (for browsers and GUI apps)

System Settings → Network → Wi-Fi (or your connection) → Details → Proxies:

- Enable **Web Proxy (HTTP)**: `PROXY_HOST_IP`, port `3128`
- Enable **Secure Web Proxy (HTTPS)**: `PROXY_HOST_IP`, port `3128`
- **Bypass proxy settings for**: `localhost,127.0.0.1`

### 5. Configure Docker Desktop

Docker Desktop → Settings → Resources → Proxies → Manual proxy configuration:

- HTTP Proxy: `http://PROXY_HOST_IP:3128`
- HTTPS Proxy: `http://PROXY_HOST_IP:3128`
- No Proxy: `localhost,127.0.0.1`

### 6. Configure npm

```bash
npm config set proxy http://PROXY_HOST_IP:3128
npm config set https-proxy http://PROXY_HOST_IP:3128
npm config set cafile ~/ca.pem
```

Or set the env var instead of `cafile`:

```bash
export NODE_EXTRA_CA_CERTS=~/ca.pem
```

Verify: `npm view lodash version`

### 7. Configure pip (optional)

pip respects `http_proxy`/`https_proxy` env vars. If you get cert errors:

```bash
pip config set global.cert ~/ca.pem
```

Or per-command:

```bash
pip install --cert ~/ca.pem somepackage
```

### 8. Configure git (optional)

git respects `http_proxy`/`https_proxy` env vars. If you get cert errors:

```bash
git config --global http.proxy http://PROXY_HOST_IP:3128
git config --global http.sslCAInfo ~/ca.pem
```

### Verify everything works

```bash
# curl
curl https://registry.npmjs.org/

# npm
npm view lodash version

# pip
pip index versions requests

# git
git ls-remote https://github.com/torvalds/linux.git HEAD
```

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

### Containers can't reach each other (503, DNS errors, "Unable to determine IP address")

The `~/.docker/config.json` `proxies` config injects `http_proxy`/`https_proxy` into **running containers too**, not just builds. Internal service-to-service calls (e.g. `http://accounts:3022`) will go through squid, which can't resolve Docker-internal hostnames.

**Fix:** List all your Docker service hostnames in `noProxy`:

```json
{
  "proxies": {
    "default": {
      "httpProxy": "http://HOST_IP:3128",
      "httpsProxy": "http://HOST_IP:3128",
      "noProxy": "localhost,127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,service1,service2,service3"
    }
  }
}
```

**Important:**
- Node.js does **not** support CIDR notation in `no_proxy` — it checks the hostname string, not the resolved IP. You must list each service hostname explicitly.
- After changing `~/.docker/config.json`, you must `docker compose up -d --force-recreate` — compose doesn't track this file for changes.

### Build arg proxy not working

Some base images don't pass build args to all stages. In multi-stage builds, re-declare the args:

```dockerfile
FROM node:20 AS builder
ARG http_proxy
ARG https_proxy
# ... rest of build
```
