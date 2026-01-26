FROM alpine:latest
RUN apk add --no-cache curl wget iperf3 tcpdump iproute2
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
