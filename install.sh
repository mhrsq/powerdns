#!/bin/bash

# Script Version
VERSION="1.0.0"

# Log file
LOG_FILE="/var/log/powerdns_install.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to check if port 53 is in use
check_port_53() {
    log_message "Checking if port 53 is in use..."
    if netstat -tuln | grep ':53' > /dev/null; then
        log_message "Port 53 is in use. Stopping conflicting services..."
        systemctl stop systemd-resolved 2>/dev/null || true
        systemctl disable systemd-resolved 2>/dev/null || true
        kill $(lsof -t -i:53) 2>/dev/null || true
    else
        log_message "Port 53 is free."
    fi
}

# Function to install and configure UFW firewall
configure_firewall() {
    log_message "Configuring UFW firewall..."
    apt install -y ufw
    ufw allow ssh
    ufw allow 53/tcp
    ufw allow 53/udp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw enable
    log_message "UFW firewall configured and enabled."
}

# Function to install PowerDNS Recursor
install_powerdns_recursor() {
    log_message "Installing PowerDNS Recursor..."
    apt update
    apt install -y pdns-recursor
    log_message "Configuring PowerDNS Recursor..."
    cat <<EOF > /etc/powerdns/recursor.conf
allow-from=127.0.0.0/8, 192.168.0.0/16, 10.0.0.0/8
local-address=0.0.0.0
local-port=53
quiet=no
hint-file=/usr/share/dns/root.hints
EOF
#    systemctl restart pdns-recursor
#    systemctl enable pdns-recursor
    log_message "PowerDNS Recursor installed and configured."
}

# Function to install PowerDNS-Admin (Web UI)
install_powerdns_admin() {
    log_message "Installing PowerDNS-Admin..."
    apt install -y git python3 python3-pip python3-venv nginx mariadb-server
    mysql_secure_installation

    # Create database and user
    log_message "Setting up MariaDB for PowerDNS-Admin..."
    mysql -e "CREATE DATABASE powerdns_admin;"
    mysql -e "CREATE USER 'powerdns_admin'@'localhost' IDENTIFIED BY 'StrongPassword123';"
    mysql -e "GRANT ALL PRIVILEGES ON powerdns_admin.* TO 'powerdns_admin'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"

    # Clone PowerDNS-Admin repository
    cd /opt
    git clone https://github.com/ngoduykhanh/PowerDNS-Admin.git powerdns-admin
    cd powerdns-admin

    # Set up Python virtual environment
    python3 -m venv env
    source env/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt

    # Configure PowerDNS-Admin
    cp config_template.py config.py
    sed -i "s/SQLA_DB_USER = .*/SQLA_DB_USER = 'powerdns_admin'/" config.py
    sed -i "s/SQLA_DB_PASSWORD = .*/SQLA_DB_PASSWORD = 'StrongPassword123'/" config.py
    sed -i "s/SQLA_DB_HOST = .*/SQLA_DB_HOST = 'localhost'/" config.py
    sed -i "s/SQLA_DB_NAME = .*/SQLA_DB_NAME = 'powerdns_admin'/" config.py

    # Initialize database
    flask db upgrade

    # Configure Nginx
    cat <<EOF > /etc/nginx/sites-available/powerdns-admin
server {
    listen 80;
    server_name yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:9191;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    ln -s /etc/nginx/sites-available/powerdns-admin /etc/nginx/sites-enabled/
    systemctl restart nginx

    log_message "PowerDNS-Admin installed and configured."
}

# Main function
main() {
    log_message "Starting PowerDNS installation script (Version: $VERSION)"
    log_message "GitHub Repository: $GITHUB_REPO"

    # Step 1: Check and free port 53
    #check_port_53

    # Step 2: Configure firewall
    configure_firewall

    # Step 3: Install PowerDNS Recursor
    install_powerdns_recursor

    # Step 4: Install PowerDNS-Admin
    install_powerdns_admin
    check_port_53
    log_message "PowerDNS installation completed successfully."
    systemctl restart pdns-recursor
    systemctl enable pdns-recursor
}

# Execute main function
main
