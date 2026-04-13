ARG ALPINE_TAG=3.23
FROM alpine:${ALPINE_TAG}

# Tools needed for the IDS validation scenario:
#   curl       - HTTP traffic generation (triggers ET Open signatures)
#   bind-tools - nslookup for DNS-lookup test
#   iproute2   - ip route for gateway configuration in entrypoint
RUN apk add --no-cache curl bind-tools iproute2

CMD ["sleep", "infinity"]
