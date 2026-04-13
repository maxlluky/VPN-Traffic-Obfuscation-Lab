ARG NGINX_IMAGE=nginx:1.27-alpine
FROM ${NGINX_IMAGE}

# Pre-install iperf3 at build time so the container never depends on
# Alpine repos being reachable at runtime.
RUN apk add --no-cache iperf3

# Start iperf3 in daemon mode, then hand off to nginx in the foreground.
CMD ["/bin/sh", "-c", "iperf3 -s -D && nginx -g 'daemon off;'"]
