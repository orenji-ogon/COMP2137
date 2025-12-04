
#!/bin/bash
# lab3.sh - Deploy configure-host.sh to servers and update local /etc/hosts
# This runs on your desktop VM. It copies the config script to each server (containers),
# runs it remotely via SSH, and then ensures your desktop VM's hosts file has the entries too.

# ---------------------------
# Debug / strict mode header
# ---------------------------
set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "[ERROR] line=$LINENO cmd=$BASH_COMMAND status=$?"' ERR

# PS4 controls the prefix for `set -x` trace lines. We guard against unset FUNCNAME at top-level.
export PS4='+ ${BASH_SOURCE[0]:-lab3.sh}:${LINENO}:${FUNCNAME[0]:-main}: '
set -x

# ---------------------------
# Parse -verbose flag from any position (safe with set -u)
# ---------------------------
verbose=""
for arg in "${@:-}"; do
  case "$arg" in
    -verbose|--verbose|-v) verbose="-verbose" ;;
  esac
done

# ---------------------------
# Function: wait until SSH answers on a server name
# ---------------------------
# We retry until an SSH command returns successfully or a timeout is hit.
wait_for_ssh() {
  local server="$1"
  local timeout="${2:-60}"      # seconds to wait (default 60)
  local start
  start=$(date +%s)

  echo "Waiting for SSH on ${server}..."
  while ! ssh -o ConnectTimeout=2 \
              -o StrictHostKeyChecking=no \
              -o UserKnownHostsFile=/dev/null \
              remoteadmin@"$server" "echo ok" >/dev/null 2>&1; do
    sleep 1
    if (( $(date +%s) - start >= timeout )); then
      echo "Error: SSH did not become ready on ${server} within ${timeout}s" >&2
      exit 1
    fi
  done
  echo "SSH is ready on ${server}"
}

# ---------------------------
# Function: copy and run configure-host.sh on a remote server
# ---------------------------
runRemote() {
  local server="$1"
  local args="$2"

  # Ensure our local script is executable (if working directory permissions allow)
  [[ -x ./configure-host.sh ]] || chmod +x ./configure-host.sh

  echo "Deploying to ${server}..."
  scp -q -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        ./configure-host.sh remoteadmin@"$server":/root

  echo "Running on ${server}..."
  # Run the script remotely; since our remote script no longer drops SSH, we can run normally.
  ssh -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      remoteadmin@"$server" "/root/configure-host.sh ${args} ${verbose}"
}

# ---------------------------
# Ensure servers are reachable
# ---------------------------
wait_for_ssh "server1-mgmt" 60
wait_for_ssh "server2-mgmt" 60

# ---------------------------
# Apply remote configs per the assignment
# ---------------------------
# server1 -> name=loghost, ip=192.168.16.3, host entry for webhost 192.168.16.4
runRemote "server1-mgmt" "-name loghost -ip 192.168.16.3 -hostentry webhost 192.168.16.4"

# server2 -> name=webhost, ip=192.168.16.4, host entry for loghost 192.168.16.3
runRemote "server2-mgmt" "-name webhost -ip 192.168.16.4 -hostentry loghost 192.168.16.3"

# ---------------------------
# Update local desktop VM /etc/hosts as well
# ---------------------------
sudo ./configure-host.sh -hostentry loghost 192.168.16.3 ${verbose}
sudo ./configure-host.sh -hostentry webhost 192.168.16.4 ${verbose}

echo "Done."
