FROM jasonish/suricata:latest

# Install python3/pip if not present (usually present in jasonish build, but ensuring for suricata-update)
# jasonish/suricata is based on Fedora or Almalinux usually, having suricata-update built-in.
# If we need lightweight, we can check alpine. 
# But for safety, let's stick to the high-quality image we probably were using, or standard one.
# The user used ${SURICATA_IMAGE}, likely jasonish/suricata.

# Ensure we have jq for JSON processing in entrypoint if needed, or python
USER root
RUN dnf install -y python3 python3-pip jq && dnf clean all

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
