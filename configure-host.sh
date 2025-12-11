#!/usr/bin/bash
# configure-host.sh - configure hostname, IP address, and /etc/hosts entries
# Quiet unless -verbose. Ignores TERM, HUP, INT. Logs changes with logger.
# Supports: -verbose, -name <desiredName>, -ip <desiredIp>, -hostentry <name> <ip>, -interface <ifname>, -finalize
# Auto-finalizes safely when connected via mgmt network (172.16.1.0/24) unless disabled.

set -Eeuo pipefail
IFS=$'\n\t'
trap '' TERM HUP INT

# ---- helpers ----
verbose=0
say() { [[ "$verbose" -eq 1 ]] && echo "$@"; }
logChange() { logger -t configure-host.sh "$*"; say "$*"; }
die() { echo "Error: $*" >&2; exit 1; }
requireRoot() { [[ "$(id -u)" -eq 0 ]] || die "must be run as root"; }

# infer peer IP from SSH environment to decide auto-finalize safety
peer_ip_from_env() {
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    # SSH_CONNECTION: "client_ip client_port server_ip server_port"
    echo "$SSH_CONNECTION" | awk '{print $1}'
  else
    # fallback — who am i may show "(client_ip)"
    who am i 2>/dev/null | awk '{print $5}' | tr -d '()'
  fi
}

in_mgmt_network() {
  local ip="$1"
  [[ "$ip" =~ ^172\.16\.1\.[0-9]+$ ]]
}

safe_to_finalize() {
  local peer
  peer=$(peer_ip_from_env || true)
  if [[ -n "$peer" ]] && in_mgmt_network "$peer"; then
    return 0
  fi
  return 1
}

# simple IPv4 validation
valid_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r o1 o2 o3 o4 <<<"$ip"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    (( o >= 0 && o <= 255 )) || return 1
  done
  return 0
}

# ---- args ----
hostNameDesired=""
ipDesired=""
hostEntryName=""
hostEntryIp=""
ifaceName=""        # default computed if blank
finalize=0          # 1 = write netplan with only ipDesired
auto_finalize=1     # auto finalize when safe

while [[ $# -gt 0 ]]; do
  case "$1" in
    -verbose|--verbose|-v) verbose=1 ;;
    -name)       shift; [[ $# -gt 0 ]] || die "-name requires a value"; hostNameDesired="$1" ;;
    -ip)         shift; [[ $# -gt 0 ]] || die "-ip requires a value";   ipDesired="$1" ;;
    -hostentry)  shift; [[ $# -gt 1 ]] || die "-hostentry requires: name ip"; hostEntryName="$1"; shift; hostEntryIp="$1" ;;
    -interface)  shift; [[ $# -gt 0 ]] || die "-interface requires a value"; ifaceName="$1" ;;
    -finalize)   finalize=1 ;;
    -no-auto-finalize) auto_finalize=0 ;;
    -auto-finalize)    auto_finalize=1 ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift || true
done

requireRoot

# ---- interface detection (if not provided) ----
detectIface() {
  local devName
  devName=$(ip route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}' | head -n1)
  [[ -n "$devName" ]] || devName="eth0"
  echo "$devName"
}
[[ -n "$ifaceName" ]] || ifaceName=$(detectIface)
say "Using interface: $ifaceName"

# ---- stage /etc/hosts temp file ----
hostsTmp=$(mktemp)
cp /etc/hosts "$hostsTmp"

# ---- hostname management (idempotent) ----
if [[ -n "$hostNameDesired" ]]; then
  currentHostName=$(hostname)
  if [[ "$currentHostName" != "$hostNameDesired" ]]; then
    echo "$hostNameDesired" > /etc/hostname
    if command -v hostnamectl >/dev/null 2>&1; then
      hostnamectl set-hostname "$hostNameDesired"
    else
      hostname "$hostNameDesired"
    fi
    # ensure 127.0.1.1 maps to desired hostname (Debian/Ubuntu convention)
    if grep -q '^127\.0\.1\.1' "$hostsTmp"; then
      sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $hostNameDesired/" "$hostsTmp"
    else
      echo "127.0.1.1 $hostNameDesired" >> "$hostsTmp"
    fi
    logChange "Hostname changed from $currentHostName to $hostNameDesired"
  else
    say "Hostname already $hostNameDesired"
  fi
fi

# ---- IP management (safe apply via netplan, preserving old IP) ----
netplanChanged=0
currentIp=""
if [[ -n "$ipDesired" ]]; then
  valid_ipv4 "$ipDesired" || die "Invalid IPv4 address: $ipDesired"

  currentIp=$(ip -4 -o addr show dev "$ifaceName" | awk '{print $4}' | sed 's#/.*##' | head -n1 || true)
  if [[ "$currentIp" != "$ipDesired" ]]; then
    say "Adding IP $ipDesired/24 on $ifaceName (current: ${currentIp:-none})"
    ip -4 addr add "$ipDesired/24" dev "$ifaceName" 2>/dev/null || true

    # Update hosts mapping for our hostname if set
    if [[ -n "$hostNameDesired" ]]; then
      sed -i "/[[:space:]]$hostNameDesired$/d" "$hostsTmp"
      printf "%s %s\n" "$ipDesired" "$hostNameDesired" >> "$hostsTmp"
    fi

    # Choose netplan file
    netplanFile=""
    if ls /etc/netplan/*.yaml >/dev/null 2>&1; then
      netplanFile=$(ls /etc/netplan/*.yaml | head -n1)
    else
      netplanFile="/etc/netplan/01-netcfg.yaml"
    fi
    cp "$netplanFile" "${netplanFile}.bak.$(date +%s)" 2>/dev/null || true

    # Build addresses: keep both during transition unless -finalize was passed
    addressesYaml="[${ipDesired}/24"
    if [[ "$finalize" -eq 0 && -n "$currentIp" && "$currentIp" != "$ipDesired" ]]; then
      addressesYaml="${addressesYaml}, ${currentIp}/24"
      say "Preserving current IP ${currentIp}/24 during netplan apply to keep SSH alive"
    fi
    addressesYaml="${addressesYaml}]"

    cat >"$netplanFile" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${ifaceName}:
      dhcp4: no
      addresses: ${addressesYaml}
EOF

    netplanChanged=1
    logChange "Netplan written on $ifaceName: addresses=${addressesYaml}"
  else
    say "IP already $ipDesired on $ifaceName"
  fi
fi

# ---- host entry ensure (idempotent) ----
if [[ -n "$hostEntryName" && -n "$hostEntryIp" ]]; then
  valid_ipv4 "$hostEntryIp" || die "Invalid IPv4 for hostentry: $hostEntryIp"
  sed -i "/[[:space:]]$hostEntryName$/d" "$hostsTmp"
  printf "%s %s\n" "$hostEntryIp" "$hostEntryName" >> "$hostsTmp"
  logChange "Host entry ensured: $hostEntryName -> $hostEntryIp"
fi

# ---- commit /etc/hosts atomically ----
if ! cmp -s "$hostsTmp" /etc/hosts; then
  cp /etc/hosts "/etc/hosts.bak.$(date +%s)"
  mv "$hostsTmp" /etc/hosts
  say "/etc/hosts updated"
else
  rm -f "$hostsTmp"
  say "No changes to /etc/hosts"
fi

# ---- apply netplan & optional auto-finalize ----
if [[ "$netplanChanged" -eq 1 ]]; then
  say "Applying netplan..."
  netplan apply || die "netplan apply failed"

  # If not explicitly finalizing, consider auto-finalize when safe
  if [[ "$finalize" -eq 0 && "$auto_finalize" -eq 1 && -n "$ipDesired" ]]; then
    if safe_to_finalize; then
      say "Auto-finalize conditions met (SSH peer on mgmt). Removing old IPs..."
      # Rewrite netplan with only desired IP
      netplanFile=""
      if ls /etc/netplan/*.yaml >/dev/null 2>&1; then
        netplanFile=$(ls /etc/netplan/*.yaml | head -n1)
      else
        netplanFile="/etc/netplan/01-netcfg.yaml"
      fi
      cat >"$netplanFile" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${ifaceName}:
      dhcp4: no
      addresses: [${ipDesired}/24]
EOF
      logChange "Netplan finalized on ${ifaceName}: address=[${ipDesired}/24]"
      netplan apply || die "netplan finalize apply failed"
    else
      say "Auto-finalize skipped: SSH peer not on mgmt or unknown. Use -finalize to complete."
    fi
  fi
fi

say "configure-host.sh completed"
