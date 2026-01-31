ARG ALPINE_TAG=3.23.2
FROM alpine:${ALPINE_TAG}

# Install obfs4proxy and dependencies
RUN apk add --no-cache \
    go \
    git \
    gcc \
    musl-dev \
    openssl-dev \
    ca-certificates

# Build obfs4proxy from source
RUN git clone https://gitlab.com/yawning/obfs4.git /tmp/obfs4 && \
    cd /tmp/obfs4/obfs4proxy && \
    go build -o /usr/local/bin/obfs4proxy && \
    cd / && \
    rm -rf /tmp/obfs4 /usr/local/go

# Create app user
RUN addgroup -g 1000 obfs4 && \
    adduser -u 1000 -G obfs4 -s /sbin/nologin -D obfs4

WORKDIR /app

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER obfs4

ENTRYPOINT ["/entrypoint.sh"]
