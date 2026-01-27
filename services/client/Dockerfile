# Default value for Alpine Linux base image
ARG ALPINE_TAG=3.23.2

# Use the specified Alpine Linux version from compose.yml
FROM alpine:${ALPINE_TAG}

# Install necessary networking tools
RUN apk add --no-cache curl wget iperf3 tcpdump iproute2

CMD ["sleep", "infinity"]