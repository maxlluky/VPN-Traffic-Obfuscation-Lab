ARG ALPINE_TAG=3.23.2
FROM alpine:${ALPINE_TAG}

# Install build dependencies
RUN apk add --no-cache git make g++ linux-headers iptables iproute2

# Build udp2raw
RUN git clone https://github.com/wangyu-/udp2raw-tunnel.git /tmp/udp2raw && \
    cd /tmp/udp2raw && \
    make dynamic && \
    cp udp2raw_dynamic /usr/local/bin/udp2raw && \
    cd / && \
    rm -rf /tmp/udp2raw

# Clean up build deps (keeping runtime deps)
RUN apk del git make g++ linux-headers && \
    apk add --no-cache libstdc++ libgcc

ENTRYPOINT ["udp2raw"]
