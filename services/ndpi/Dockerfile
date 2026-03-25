ARG ALPINE_TAG=3.23

# ── Build stage: compile nDPI from source ────────────────────────
FROM alpine:${ALPINE_TAG} AS builder

ARG NDPI_VERSION=5.0

RUN apk add --no-cache \
        git autoconf automake libtool gcc g++ make \
        libpcap-dev linux-headers json-c-dev

RUN git clone --branch ${NDPI_VERSION} --depth 1 \
        https://github.com/ntop/nDPI.git /tmp/nDPI \
    && cd /tmp/nDPI \
    && ./autogen.sh \
    && ./configure --prefix=/usr \
    && make -j"$(nproc)" \
    && make install DESTDIR=/tmp/install

# ── Runtime stage: minimal image with only ndpiReader ────────────
FROM alpine:${ALPINE_TAG}

RUN apk add --no-cache libpcap json-c libstdc++

COPY --from=builder /tmp/install/usr/bin/ndpiReader /usr/bin/ndpiReader
COPY --from=builder /tmp/install/usr/lib/libndpi* /usr/lib/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
