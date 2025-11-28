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
PRIMARY_FILE=$(basename "$NETPLAN_FILE")

log "Checking for conflicting Netplan configuration files..."
for file in /etc/netplan/*.yaml; do
    base=$(basename "$file")
    if [ "$base" != "$PRIMARY_FILE" ]; then
        log "Disabling conflicting Netplan file: $base"
        mv "$file" "/etc/netplan/${base}.bak" || { error "Failed to disable $base"; exit 1; }
        success "$base has been backed up as ${base}.bak"
    fi
done

if [ ! -f "$NETPLAN_FILE" ]; then
    log "Netplan file not found. Creating a basic one..."
    cat <<EOF > "$NETPLAN_FILE" || { error "Failed to create netplan file"; exit 1; }
network:
    version: 2
    renderer: networkd
    ethernets:
        eth0:
            addresses: [192.168.16.21/24]
            routes:
              - to: default
                via: 192.168.16.2
            nameservers:
                addresses: [192.168.16.2]
                search: [home.arpa, localdomain]
        eth1:
            addresses: [172.16.1.241/24]
EOF
	chmod 600 "$NETPLAN_FILE"
	success "Netplan file created."

# Apply right after creation
log "Applying netplan configuration..."
netplan apply || { error "Netplan apply failed"; exit 1; }
success "Netplan applied successfully."

fi

# Step 2: Update /etc/hosts
log "Ensuring /etc/hosts has the correct entry for server1..."

# Remove any existing 'server1' line (but not server1-mgmt or others)
sed -i '/server1$/d' /etc/hosts || { error "Failed to remove old server1 entry"; exit 1; }

# Add the correct address mapping
echo "192.168.16.21 server1" >> /etc/hosts || { error "Failed to add server1 entry"; exit 1; }

success "/etc/hosts updated for server1"


# Wait until DNS resolution succeeds
#for i in {1..10}; do
#   if ping -c1 archive.ubuntu.com &>/dev/null; then
#        echo "[SUCCESS] DNS is working."
#        break
#    fi
#    echo "[INFO] Waiting for DNS to settle..."
#    sleep 3
#done

# Step 3: Install apache2 and squid if missing, otherwise check status
log "Checking apache2 and squid..."

# Always refresh repo list once at the start
apt-get update -qq || { error "Failed to update repo list"; exit 1; }

for pkg in apache2 squid; do
    installed_version=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)	# installed_version is version that is currently running
    newest_version=$(apt-cache policy "$pkg" | awk '/Candidate:/ {print $2}')	# newest_version is version that is available not installed

    if [ -z "$installed_version" ]; then
        log "$pkg not found. Installing..."
        apt-get install -y "$pkg" || { error "Failed to install $pkg"; exit 1; }
        installed_version=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null)
        success "$pkg installed (version $installed_version)."
    else
        success "$pkg already installed (version $installed_version)."

        # Check service is enabled
        if systemctl is-enabled --quiet "$pkg"; then
            success "$pkg service is enabled."
        else
            log "Enabling $pkg service..."
            systemctl enable "$pkg" || error "Failed to enable $pkg"
        fi

        # Check service is running
        if systemctl is-active --quiet "$pkg"; then
            success "$pkg service is running."
        else
            log "Starting $pkg service..."
            systemctl start "$pkg" || error "Failed to start $pkg"
        fi
    fi

    # Show version info
    echo "-----------------------------------"
    echo "$pkg installed version: ${installed_version:-not installed}"
    echo "$pkg latest available version: $newest_version"
    if [ "$installed_version" != "$newest_version" ]; then
        echo "$pkg is out of date (installed: $installed_version, latest: $newest_version)"
    else
        echo "$pkg is up to date (version $installed_version)"
    fi
    echo "-----------------------------------"
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

