#!/bin/bash
# PowerDNS Recursive DNS Server Installation Script
# Compatible with Debian 12
# Version: 1.1
# Author: Your Name

set -e

# Variables
PDNS_CONFIG="/etc/powerdns/recursor.conf"
FIREWALLD_SERVICE="firewalld"

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# Update and install dependencies
echo "Updating system and installing dependencies..."
apt update && apt upgrade -y
apt install -y pdns-recursor firewalld unattended-upgrades

# Configure PowerDNS Recursor
echo "Configuring PowerDNS Recursor..."
cat <<EOF > $PDNS_CONFIG
allow-from=127.0.0.0/8, 192.168.0.0/16, 10.0.0.0/8
local-address=0.0.0.0
dnssec=validate
rate-limit=200
max-qperq=50
max-packetcache-entries=100000
max-cache-entries=1000000
loglevel=2
quiet=yes
EOF

# Restart PowerDNS Recursor systemd service
echo "Restarting PowerDNS Recursor service..."
systemctl enable pdns-recursor
systemctl restart pdns-recursor

# Configure firewall (Firewalld best practice per KINDNS)
echo "Configuring Firewalld rules..."
systemctl enable --now firewalld
firewall-cmd --permanent --set-default-zone=drop
firewall-cmd --permanent --add-service=dns
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.0/16" accept'
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" accept'
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="127.0.0.0/8" accept'
firewall-cmd --reload

# Enable automatic security updates
echo "Configuring automatic security updates..."
dpkg-reconfigure --priority=low unattended-upgrades

# Verify service status
echo "Checking service status..."
systemctl status pdns-recursor --no-pager

echo "PowerDNS Recursive DNS installation completed successfully!"
