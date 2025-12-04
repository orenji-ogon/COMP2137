# Run in containers after running lab3.sh to push and install configure-host.sh into server1 and 2

# after configure-host.sh this should show;
# Desired hostname
hostname
cat /etc/hostname

# Hosts entries should include both machines
grep -E '^(192\.168\.16\.(3|4))' /etc/hosts

# Netplan should have addresses: [DESIRED_IP/24] under the correct interface,
# and should preserve any routes/nameservers that were there.
ls -l /etc/netplan
cat /etc/netplan/*.yaml

# Interface should include the desired IP; old IP may remain (SSH-safe)
intFace=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print $NF; exit}')
[ -n "$intFace" ] || intFace="eth0"
ip -4 addr show dev "$intFace"
