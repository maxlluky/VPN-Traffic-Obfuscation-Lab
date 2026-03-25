ARG SURICATA_IMAGE=jasonish/suricata:8.0.3
FROM ${SURICATA_IMAGE}

# Install jq and python3 for suricata-update and entrypoint
USER root
RUN dnf install -y python3 python3-pip jq && dnf clean all

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
