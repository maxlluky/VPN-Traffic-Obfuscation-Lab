ARG ALPINE_TAG=3.23
FROM alpine:${ALPINE_TAG}

# Pre-install iptables at build time so the container never depends on
# Alpine repos being reachable at runtime.
RUN apk add --no-cache iptables

CMD ["tail", "-f", "/dev/null"]
