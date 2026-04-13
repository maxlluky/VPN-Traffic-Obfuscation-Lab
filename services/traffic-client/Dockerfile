# Default value for Alpine Linux base image
ARG ALPINE_TAG=3.23

# Use the specified Alpine Linux version from compose.yml
FROM alpine:${ALPINE_TAG}

# Install necessary networking tools
RUN apk add --no-cache \
    curl \
    iperf3 \
    bind-tools \
    iproute2 \
    python3 \
    py3-requests

COPY traffic_gen.py /usr/local/bin/traffic_gen.py
RUN chmod +x /usr/local/bin/traffic_gen.py

CMD ["sleep", "infinity"]