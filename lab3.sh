#!/usr/bin/bash
set -euo pipefail

# Pass -verbose through if present
verboseFlag=""
[[ "${1:-}" == "-verbose" ]] && verboseFlag="-verbose"

#less strict about rebuilt containers (skip strict host key checks for this run)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

# Server 1: loghost
scp $SSH_OPTS configure-host.sh remoteadmin@server1-mgmt:/root/
ssh $SSH_OPTS remoteadmin@server1-mgmt -- /root/configure-host.sh $verboseFlag \
  -name loghost -ip 192.168.16.3 -hostentry webhost 192.168.16.4

# Server 2: webhost
scp $SSH_OPTS configure-host.sh remoteadmin@server2-mgmt:/root/
ssh $SSH_OPTS remoteadmin@server2-mgmt -- /root/configure-host.sh $verboseFlag \
  -name webhost -ip 192.168.16.4 -hostentry loghost 192.168.16.3

# Update local desktop VM /etc/hosts (requires sudo)
sudo ./configure-host.sh $verboseFlag -hostentry loghost 192.168.16.3
sudo ./configure-host.sh $verboseFlag -hostentry webhost 192.168.16.4
