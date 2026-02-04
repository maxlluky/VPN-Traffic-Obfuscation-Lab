ARG ALPINE_TAG=3.23
FROM alpine:${ALPINE_TAG} as builder

RUN apk add --no-cache make g++ linux-headers unzip wget

WORKDIR /tmp
# Download specific release from the correct repo (wangyu-/udp2raw)
RUN wget -O source.zip https://github.com/wangyu-/udp2raw/archive/refs/tags/20230206.0.zip && \
    unzip source.zip && \
    mv udp2raw-20230206.0 udp2raw

WORKDIR /tmp/udp2raw
RUN make

FROM alpine:${ALPINE_TAG}
RUN apk add --no-cache libstdc++ iptables iproute2
COPY --from=builder /tmp/udp2raw/udp2raw /usr/bin/udp2raw

CMD ["udp2raw"]
