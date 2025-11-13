#!/bin/bash

# Make the script safe: stop on errors, undefined variables, or broken pipelines
set -euo pipefail
IFS=$'\n\t'

# Logging functions
log() {
    echo -e "\n[INFO] $1"
}

success() {
    echo -e "\n[SUCCESS] $1"
}

error() {
    echo -e "\n[ERROR] $1" >&2
}

# Step 1: Configure Netplan
log "Checking netplan configuration for 192.168.16.21..."

NETPLAN_FILE="/etc/netplan/01-netconfig.yaml"

if [ ! -f "$NETPLAN_FILE" ]; then
    log "Netplan file not found. Creating a basic one..."
    cat <<EOF > "$NETPLAN_FILE" || { error "Failed to create netplan file"; exit 1; }
network:
  version: 2
  ethernets:
    eth0:
      addresses: [192.168.16.21/24]
      gateway4: 192.168.16.1
      nameservers:
        addresses: [8.8.8.8,8.8.4.4]
      routes:
        - to: 0.0.0.0/0
          via: 192.168.16.1

EOF
    success "Netplan file created."
fi

if ! grep -q "192.168.16.21/24" "$NETPLAN_FILE"; then
    log "Updating netplan configuration..."
    sed -i '/addresses:/c\      addresses: [192.168.16.21/24]' "$NETPLAN_FILE" || { error "Failed to update netplan file"; exit 1; }
    netplan apply || { error "Netplan apply failed"; exit 1; }
    success "Netplan updated and applied."
else
    success "Netplan already correctly configured."
fi

# Step 2: Update /etc/hosts
log "Checking /etc/hosts for correct entry for server1..."

if grep -q "server1" /etc/hosts && ! grep -q "192.168.16.21 server1" /etc/hosts; then
    log "Removing outdated server1 entry..."
    sed -i '/server1/d' /etc/hosts || { error "Failed to remove old server1 entry"; exit 1; }
fi

if ! grep -q "192.168.16.21 server1" /etc/hosts; then
    echo "192.168.16.21 server1" >> /etc/hosts || { error "Failed to add server1 to /etc/hosts"; exit 1; }
    success "/etc/hosts updated."
else
    success "/etc/hosts already correct."
fi

# Wait until DNS resolution succeeds
#for i in {1..10}; do
#   if ping -c1 archive.ubuntu.com &>/dev/null; then
#        echo "[SUCCESS] DNS is working."
#        break
#    fi
#    echo "[INFO] Waiting for DNS to settle..."
#    sleep 3
#done

# Step 3: Install apache2 and squid
log "Installing apache2 and squid..."

for pkg in apache2 squid; do
    if ! dpkg -l | grep -qw "$pkg"; then
        log "Installing $pkg..."
        apt-get update && apt-get install -y "$pkg" || { error "Failed to install $pkg"; exit 1; }
        success "$pkg installed."
    else
        success "$pkg already installed."
    fi
done

# Step 4: Create users and SSH keys
log "Creating user accounts and configuring SSH keys..."

USERS=(dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda)
EXTRA_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"

for user in "${USERS[@]}"; do
    if ! id "$user" &>/dev/null; then
        log "Creating user $user..."
        useradd -m -s /bin/bash "$user" || { error "Failed to create user $user"; exit 1; }
        success "User $user created."
    else
        success "User $user already exists."
    fi

    SSH_DIR="/home/$user/.ssh"
    AUTH_KEYS="$SSH_DIR/authorized_keys"

    log "Setting up SSH for $user..."
    mkdir -p "$SSH_DIR" || { error "Failed to create $SSH_DIR"; exit 1; }
    touch "$AUTH_KEYS" || { error "Failed to create $AUTH_KEYS"; exit 1; }
    chmod 700 "$SSH_DIR"
    chmod 600 "$AUTH_KEYS"
    chown -R "$user:$user" "$SSH_DIR"

    # Generate SSH keys if missing
    if [ ! -f "$SSH_DIR/id_rsa.pub" ]; then
        sudo -u "$user" ssh-keygen -t rsa -N "" -f "$SSH_DIR/id_rsa" || { error "RSA keygen failed for $user"; exit 1; }
    fi
    if [ ! -f "$SSH_DIR/id_ed25519.pub" ]; then
        sudo -u "$user" ssh-keygen -t ed25519 -N "" -f "$SSH_DIR/id_ed25519" || { error "ED25519 keygen failed for $user"; exit 1; }
    fi

    # Add public keys to authorized_keys
    for keyfile in "$SSH_DIR"/id_*.pub; do
        grep -qxF "$(cat "$keyfile")" "$AUTH_KEYS" || cat "$keyfile" >> "$AUTH_KEYS"
    done

    # Special setup for dennis
    if [ "$user" == "dennis" ]; then
        grep -qxF "$EXTRA_KEY" "$AUTH_KEYS" || echo "$EXTRA_KEY" >> "$AUTH_KEYS"
        usermod -aG sudo dennis || { error "Failed to add dennis to sudo group"; exit 1; }
        success "Dennis configured with sudo and extra SSH key."
    fi
done

