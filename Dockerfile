FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        squid-openssl \
        squidclient \
        openssl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY squid.conf /etc/squid/squid.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3128

ENTRYPOINT ["/entrypoint.sh"]
