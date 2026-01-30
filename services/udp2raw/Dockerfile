ARG ALPINE_TAG=3.23.2
FROM alpine:${ALPINE_TAG}

# Install build dependencies
RUN apk add --no-cache git make g++ linux-headers

# Build udp2raw
RUN git clone https://github.com/wangyu-/udp2raw-tunnel.git /tmp/udp2raw && \
    cd /tmp/udp2raw && \
    make dynamic && \
    cp udp2raw_dynamic /usr/local/bin/udp2raw && \
    cd / && \
    rm -rf /tmp/udp2raw

# Clean up build deps (optional, keeping it simple for now)

ENTRYPOINT ["udp2raw"]
