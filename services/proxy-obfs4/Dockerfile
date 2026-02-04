ARG ALPINE_TAG=3.23.2
FROM alpine:${ALPINE_TAG}

# Install obfs4proxy and dependencies
RUN apk add --no-cache \
    shadowsocks-rust \
    go \
    git \
    gcc \
    musl-dev \
    openssl-dev \
    ca-certificates \
    bash \
    python3

# Build obfs4proxy from source
RUN git clone https://gitlab.com/yawning/obfs4.git /tmp/obfs4 && \
    cd /tmp/obfs4/obfs4proxy && \
    go build -o /usr/local/bin/obfs4proxy && \
    cd / && \
    rm -rf /tmp/obfs4 /usr/local/go

# Setup State Directory and Generate Keys
# We verify the directory ownership and permissions
RUN mkdir -p /var/lib/obfs4 && \
    chown -R 1000:1000 /var/lib/obfs4

WORKDIR /var/lib/obfs4

# Generate keys during build for reproducibility.
# We run obfs4proxy briefly to force it to generate the state files.
# We then verify the output to extract the 'cert' parameter which is needed by clients.
RUN export TOR_PT_MANAGED_TRANSPORT_VER=1 \
    export TOR_PT_STATE_LOCATION=/var/lib/obfs4 \
    export TOR_PT_SERVER_TRANSPORTS=obfs4 \
    export TOR_PT_SERVER_BINDADDR=obfs4-0.0.0.0:12345 \
    export TOR_PT_ORPORT=127.0.0.1:51820 \
    && timeout 5s /usr/local/bin/obfs4proxy > /var/lib/obfs4/output.log 2>&1 || true \
    && cat /var/lib/obfs4/output.log \
    && echo "Extracting cert..." \
    && grep "obfs4" /var/lib/obfs4/output.log | grep "cert=" | sed 's/.*cert=//' | awk -F ';' '{print $1}' > /public_cert.txt \
    && echo "Generated Cert: $(cat /public_cert.txt)" \
    && if [ ! -s /public_cert.txt ]; then echo "Failed to generate cert!"; exit 1; fi \
    && chown 1000:1000 /public_cert.txt /var/lib/obfs4/*

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
COPY pt_adapter.py /usr/local/bin/pt_adapter.py
RUN chmod +x /entrypoint.sh /usr/local/bin/pt_adapter.py

USER 1000
ENTRYPOINT ["/entrypoint.sh"]
