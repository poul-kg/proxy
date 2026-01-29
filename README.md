# Squid Caching Proxy for Docker Builds

A caching HTTP/HTTPS proxy that speeds up `docker compose build` by caching package downloads from apt, npm, pip, Go modules, and any other HTTP/HTTPS traffic.

Runs as a Docker container. Other machines on the network can use it too.

## Quick Start

```bash
# 1. Generate the CA certificate (one-time)
./scripts/generate-ca.sh

# 2. Copy environment config
cp .env.example .env

# 3. Build and start the proxy
docker compose up -d --build

# 4. Verify it's running
docker compose logs -f
```

The proxy is now running on port **3128**.

## Using the Proxy for Docker Builds

Pass proxy settings as build args. This only affects the build — running containers are not proxied.

```bash
docker compose build \
  --build-arg HTTP_PROXY=http://HOST_IP:3128 \
  --build-arg HTTPS_PROXY=http://HOST_IP:3128
```

Replace `HOST_IP` with your machine's LAN IP (not `localhost` — Docker build runs in an isolated network).

Find your IP: `hostname -I | awk '{print $1}'`

### Trust the CA Certificate in Dockerfiles

Since the proxy intercepts HTTPS (SSL bump), build containers need to trust the proxy's CA certificate. Add these lines to your Dockerfiles.

**Debian / Ubuntu:**

```dockerfile
COPY path/to/proxy/certs/ca.pem /usr/local/share/ca-certificates/squid-ca.crt
RUN update-ca-certificates
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt
ENV NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/squid-ca.crt
```

**Alpine:**

```dockerfile
COPY path/to/proxy/certs/ca.pem /usr/local/share/ca-certificates/squid-ca.crt
RUN update-ca-certificates
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt
ENV NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/squid-ca.crt
```

**RHEL / Fedora / CentOS:**

```dockerfile
COPY path/to/proxy/certs/ca.pem /etc/pki/ca-trust/source/anchors/squid-ca.pem
RUN update-ca-trust
ENV REQUESTS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt
ENV PIP_CERT=/etc/pki/tls/certs/ca-bundle.crt
ENV NODE_EXTRA_CA_CERTS=/etc/pki/ca-trust/source/anchors/squid-ca.pem
```

**Go:** respects the system CA store after `update-ca-certificates`, no extra env var needed.

### Multi-stage builds

Some base images don't pass build args to all stages. Re-declare the args:

```dockerfile
FROM node:20 AS builder
ARG HTTP_PROXY
ARG HTTPS_PROXY
# ... rest of build
```

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

### 5. Configure npm

```bash
npm config set proxy http://PROXY_HOST_IP:3128
npm config set https-proxy http://PROXY_HOST_IP:3128
npm config set cafile ~/ca.pem
```

Or set the env var instead of `cafile`:

```bash
export NODE_EXTRA_CA_CERTS=~/ca.pem
```

### 6. Configure pip (optional)

pip respects `http_proxy`/`https_proxy` env vars. If you get cert errors:

```bash
pip config set global.cert ~/ca.pem
```

### 7. Configure git (optional)

git respects `http_proxy`/`https_proxy` env vars. If you get cert errors:

```bash
git config --global http.proxy http://PROXY_HOST_IP:3128
git config --global http.sslCAInfo ~/ca.pem
```

## Storage Management

### Check cache usage

```bash
./scripts/check-storage.sh
```

### Clean all cached data

```bash
./scripts/clean-cache.sh
```

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

| Setting | Default |
|---------|---------|
| Cache size | 100 GB |
| Max object size | 1 GB |
| RAM cache | 512 MB |
| Default retention | 365 days |

## Troubleshooting

### "certificate verify failed" errors

The CA cert is not trusted in the build container. Make sure your Dockerfile copies and trusts `ca.pem` (see above).

### Squid won't start

```bash
docker compose logs squid
```

Common issues:
- Missing CA cert: run `./scripts/generate-ca.sh` first
- Port 3128 in use: change `PROXY_PORT` in `.env`
- Cache dir permissions: try `sudo chown -R 13:13 cache_dir/`

### Firewall

If other machines need to reach the proxy, open port 3128:

```bash
sudo firewall-cmd --add-port=3128/tcp --permanent
sudo firewall-cmd --reload
```
