#!/bin/bash

apt autoremove --purge pdns-recursor -y
rm -rf /etc/powerdns
echo "[+] Powerdns removed successfully"

systemctl start systemd-resolved
systemctl enable systemd-resolved
echo "[+] Systemd-resolved services restored successfully"
echo "[+] Scheduling reboot in 1 minute..."
shutdown -r +1
