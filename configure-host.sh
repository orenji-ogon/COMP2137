#!/bin/bash
# configure-host.sh - Configure hostname, IP address, and /etc/hosts entries
# Quiet unless -verbose; ignores TERM/HUP/INT; logs changes with logger.

set -Eeuo pipefail
IFS=$'\n\t'
trap '' TERM HUP INT

# --- Helpers ---
verbose=0
say() { [[ $verbose -eq 1 ]] && echo "$@"; }
logChange() { logger -t configure-host.sh "$*"; say "$*"; }
die() { echo "Error: $*" >&2; exit 1; }
require_root() { [[ $(id -u) -eq 0 ]] || die "must be run as root"; }

# --- Parse arguments (robust, idempotent-friendly) ---
hostNameDesired=""
ipDesired=""
hostEntryName=""
hostEntryIp=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -verbose|--verbose|-v) verbose=1 ;;
    -name)
      shift; [[ $# -gt 0 ]] || die "-name requires a value"
      hostNameDesired="$1"
      ;;
    -ip)
      shift; [[ $# -gt 0 ]] || die "-ip requires a value"
      ipDesired="$1"
      ;;
    -hostentry)
      shift; [[ $# -gt 1 ]] || die "-hostentry requires: name ip"
      hostEntryName="$1"; shift
      hostEntryIp="$1"
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift || true
done

require_root

# --- Detect primary interface (default route dev; fallback to eth0) ---
detect_iface() {
  local dev
  dev=$(ip route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}' | head -n1)
  [[ -n "$dev" ]] || dev="eth0"
  echo "$dev"
}
iface=$(detect_iface)
say "Using interface: $iface"

# --- Prepare hosts temp file (all edits staged & committed atomically) ---
hosts_tmp=$(mktemp)
cp /etc/hosts "$hosts_tmp"

# --- Hostname management (idempotent, quiet unless verbose) ---
if [[ -n "$hostNameDesired" ]]; then
  currentHostName=$(hostname)
  if [[ "$currentHostName" != "$hostNameDesired" ]]; then
    echo "$hostNameDesired" > /etc/hostname
    if command -v hostnamectl >/dev/null 2>&1; then
      hostnamectl set-hostname "$hostNameDesired"
    else
      hostname "$hostNameDesired"
    fi
    # Ensure 127.0.1.1 maps to desired hostname (Debian/Ubuntu convention)
    if grep -q '^127\.0\.1\.1' "$hosts_tmp"; then
      sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $hostNameDesired/" "$hosts_tmp"
    else
      echo "127.0.1.1 $hostNameDesired" >> "$hosts_tmp"
    fi
    logChange "Hostname changed from $currentHostName to $hostNameDesired"
  else
    say "Hostname already $hostNameDesired"
  fi
fi

# --- IP management (add new IP first, do NOT flush/remove old IP; netplan rewrite) ---
netplan_changed=0
if [[ -n "$ipDesired" ]]; then
  # current primary IPv4 on iface
  currentIp=$(ip -4 -o addr show dev "$iface" | awk '{print $4}' | sed 's#/.*##' | head -n1 || true)
  if [[ "$currentIp" != "$ipDesired" ]]; then
    say "Adding IP $ipDesired/24 on $iface (current primary: ${currentIp:-none})"
    # Add new address first to avoid dropping SSH
    ip -4 addr add "$ipDesired/24" dev "$iface" 2>/dev/null || true

    # Update hosts mapping for our hostname if provided (idempotent)
    if [[ -n "$hostNameDesired" ]]; then
      # Remove any existing lines that end with the hostname, then add desired mapping
      sed -i "/[[:space:]]$hostNameDesired$/d" "$hosts_tmp"
      printf "%s %s\n" "$ipDesired" "$hostNameDesired" >> "$hosts_tmp"
    fi

    # Netplan: choose file, backup, and write a deterministic static config
    netplan_file=""
    if ls /etc/netplan/*.yaml >/dev/null 2>&1; then
      netplan_file=$(ls /etc/netplan/*.yaml | head -n1)
    else
      netplan_file="/etc/netplan/01-netcfg.yaml"
    fi
    cp "$netplan_file" "${netplan_file}.bak.$(date +%s)" 2>/dev/null || true
    cat >"$netplan_file" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${iface}:
      dhcp4: no
      addresses: [${ipDesired}/24]
EOF
    netplan_changed=1

    logChange "IP ensured on $iface: ${currentIp:-none} -> $ipDesired (existing IPs retained)"
  else
    say "IP already $ipDesired on $iface"
  fi
fi

# --- Host entry ensure (idempotent, quiet unless verbose) ---
if [[ -n "$hostEntryName" && -n "$hostEntryIp" ]]; then
  sed -i "/[[:space:]]$hostEntryName$/d" "$hosts_tmp"
  printf "%s %s\n" "$hostEntryIp" "$hostEntryName" >> "$hosts_tmp"
  logChange "Host entry ensured: $hostEntryName -> $hostEntryIp"
fi

# --- Commit /etc/hosts atomically ---
if ! cmp -s "$hosts_tmp" /etc/hosts; then
  cp /etc/hosts "/etc/hosts.bak.$(date +%s)"
  mv "$hosts_tmp" /etc/hosts
  say "/etc/hosts updated"
else
  rm -f "$hosts_tmp"
  say "No changes to /etc/hosts"
fi

# --- Apply netplan if changed (this may promote the desired IP) ---
if [[ "$netplan_changed" -eq 1 ]]; then
  say "Applying netplan..."
  netplan apply || die "netplan apply failed"
fi

say "configure-host.sh completed"
