# Enable JSON logging
@load policy/tuning/json-logs

# Load standard protocols
@load base/protocols/conn
@load base/protocols/dns
@load base/protocols/http
@load base/protocols/ssl

# Load notice framework
@load base/frameworks/notice

# Optional: Add community id
# @load packages/zeek-community-id
