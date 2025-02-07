#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "[+] Please run this script as root (sudo)."
  exit 1
fi

echo "[+] Checking for existing services using port 53..."
EXISTING_SERVICE=$(ss -tulpn | grep ':53 ' | awk '{print $NF}' | cut -d'"' -f2 | sort -u)
if [[ -n "$EXISTING_SERVICE" ]]; then
  echo "[!] Port 53 is already in use by: $EXISTING_SERVICE"
  echo "[+] Stopping and disabling the conflicting service(s)..."
  if [ "$EXISTING_SERVICE" == "systemd-resolve" ]; then
      systemctl stop systemd-resolved
      systemctl disable systemd-resolved
  else
      systemctl stop $EXISTING_SERVICE
      systemctl disable $EXISTING_SERVICE
  fi
  echo "[+] Service(s) stopped and disabled. Proceeding with PowerDNS setup."
else
  echo "[+] Port 53 is free. Proceeding with PowerDNS setup."
fi

echo "[+] Updating package repositories..."
apt-get update

echo "[+] Installing pdns-recursor and required packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y pdns-recursor curl iptables-persistent

echo "[+] Detecting IP Addresses"
# Detect Public IPv4 and IPv6 addresses
PUBLIC_IPV4=$(curl -s -4 ifconfig.me || curl -s ifconfig.co)
PUBLIC_IPV6=$(curl -s ifconfig.co)

# Detect Private IPv4 and IPv6 Networks
PRIVATE_IPV4=$(hostname -I | awk '{print $1}')
PRIVATE_IPV6=$(ip -6 addr show scope global | awk '/inet6/ {print $2}' | head -n 1)

if [[ -z "$PRIVATE_IPV6" ]]; then
  PRIVATE_IPV6="No IPv6 detected"
fi

echo "[+] Creating a new configuration file for pdns-recursor..."
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

# Enable root hint
hint-file=/usr/share/dns/root.hints

# Enable Hyperlocal Root Zones
include-dir=/etc/powerdns/hyperlocal
EOF

mkdir -p /etc/powerdns/hyperlocal
cat <<EOF > /etc/powerdns/hyperlocal/root.zone
. 86400 IN SOA root. root.localhost. 1 86400 7200 604800 86400
. 86400 IN NS localhost.
localhost. 86400 IN A 127.0.0.1
localhost. 86400 IN AAAA ::1
EOF

echo "[+] Restarting pdns-recursor..."
systemctl restart pdns-recursor

echo "[+] Enabling pdns-recursor service..."
systemctl enable pdns-recursor

echo "[+] Installation and configuration completed following KINDNS best practices. below are the current pdns-recursor status:"
systemctl status pdns-recursor | grep -i active

echo "[+] Configuring Firewall with Port Knocking..."
# Define knock sequence (high ports)
KNOCK_PORTS=(50000 51000 52000)
KNOCK_TIMEOUT=20

# Flush existing rules
iptables -F
ip6tables -F

# Default drop policy
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

# Allow localhost traffic
iptables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT

# Allow established and related connections
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Allow DNS service without port knocking
iptables -A INPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --dport 53 -j ACCEPT
ip6tables -A INPUT -p tcp --dport 53 -j ACCEPT
ip6tables -A INPUT -p udp --dport 53 -j ACCEPT

# Allow Port Knocking sequence for SSH, HTTP, and HTTPS
iptables -N KNOCKING
iptables -A INPUT -p tcp --dport ${KNOCK_PORTS[0]} -m recent --name KNOCK1 --set -j DROP
iptables -A INPUT -p tcp --dport ${KNOCK_PORTS[1]} -m recent --rcheck --seconds $KNOCK_TIMEOUT --name KNOCK1 -m recent --name KNOCK2 --set -j DROP
iptables -A INPUT -p tcp --dport ${KNOCK_PORTS[2]} -m recent --rcheck --seconds $KNOCK_TIMEOUT --name KNOCK2 -m recent --name AUTHORIZED --set -j DROP

# Allow access to SSH, HTTP, and HTTPS after successful knocking
iptables -A INPUT -p tcp --dport 22 -m recent --rcheck --name AUTHORIZED -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -m recent --rcheck --name AUTHORIZED -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -m recent --rcheck --name AUTHORIZED -j ACCEPT
ip6tables -A INPUT -p tcp --dport 22 -m recent --rcheck --name AUTHORIZED -j ACCEPT
ip6tables -A INPUT -p tcp --dport 80 -m recent --rcheck --name AUTHORIZED -j ACCEPT
ip6tables -A INPUT -p tcp --dport 443 -m recent --rcheck --name AUTHORIZED -j ACCEPT

# Save firewall rules
netfilter-persistent save > /dev/null 2>&1

echo "[+] Firewall configuration completed with port knocking enabled for SSH, HTTP, and HTTPS."
echo "[+] Port Knocking Sequence: 50000 -> 51000 -> 52000 -> SSH/HTTP/HTTPS"
echo "----------------------------------"
echo "--- General Access Information ---"
echo "Public IPv4: $PUBLIC_IPV4"
echo "Public IPv6: $PUBLIC_IPV6"
echo "Private IPv4: $PRIVATE_IPV4"
echo "Private IPv6: $PRIVATE_IPV6"
