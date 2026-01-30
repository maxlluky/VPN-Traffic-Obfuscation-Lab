FROM alpine:latest
RUN apk add --no-cache wireguard-tools iproute2 iptables tcpdump
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
