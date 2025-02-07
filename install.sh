#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "Please run this script as root (sudo)."
  exit 1
fi

echo "Updating package repositories..."
apt-get update

echo "Installing pdns-recursor..."
apt-get install -y pdns-recursor curl

# Detect Public IPv4 and IPv6 addresses
PUBLIC_IPV4=$(curl -s ifconfig.me || curl -s icanhazip.com)
PUBLIC_IPV6=$(curl -s -6 ifconfig.me || echo "No IPv6 detected")

# Detect Private IPv4 and IPv6 Networks
PRIVATE_IPV4=$(hostname -I | awk '{print $1}')
PRIVATE_IPV6=$(ip -6 addr show scope global | awk '/inet6/ {print $2}' | head -n 1)

if [[ -z "$PRIVATE_IPV6" ]]; then
  PRIVATE_IPV6="No IPv6 detected"
fi

echo "Creating a new configuration file for pdns-recursor..."
cat <<EOF > /etc/powerdns/recursor.conf
# PowerDNS Recursor Configuration
quiet=no

# Listen on all IPv4 addresses
local-address=0.0.0.0

# Allow queries from localhost and local network (adjust as needed)
allow-from=127.0.0.1,$PRIVATE_IPV4/24

# Enable DNSSEC validation
dnssec=validate

# Enable QNAME Minimization to improve privacy
qname-minimization=yes

# Limit DNS query logging retention
log-common-errors=yes

# Enable Monitoring
webserver=yes
webserver-address=127.0.0.1
webserver-port=8082
webserver-loglevel=normal

EOF

echo "Restarting pdns-recursor..."
systemctl restart pdns-recursor

echo "Enabling pdns-recursor service..."
systemctl enable pdns-recursor

echo "Installation and configuration completed following KINDNS best practices."
systemctl status pdns-recursor
echo "----------------------------------"
echo "--- General Access Information ---"
echo "Public IPv4: $PUBLIC_IPV4"
echo "Public IPv6: $PUBLIC_IPV6"
echo "Private IPv4: $PRIVATE_IPV4"
echo "Private IPv6: $PRIVATE_IPV6"
