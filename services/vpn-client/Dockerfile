ARG ALPINE_TAG=3.23
FROM alpine:${ALPINE_TAG}
RUN apk add --no-cache wireguard-tools iproute2 iptables
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]