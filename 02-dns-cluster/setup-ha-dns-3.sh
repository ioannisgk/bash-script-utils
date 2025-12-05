#!/bin/bash

# Disable systemd-resolved which binds to port 53 and conflicts with bind
systemctl disable --now systemd-resolved
rm -f /etc/resolv.conf

# Set temporary dns server to download packages
echo "nameserver 8.8.8.8" | tee /etc/resolv.conf

# Install bind and keepalived
apt update
apt install -y bind9 bind9utils bind9-doc keepalived

echo "Gathering network information..."

# Detect the active network interface
INTERFACE=$(ip route show default | awk '/default/ {print $5}' | head -n1)

# Calculate the network cidr
NETWORK_CIDR=$(ip route | grep "dev $INTERFACE" | grep "proto kernel" | awk '{print $1}' | head -n1)

# Edit the dns zone to add the trusted network acl
cat <<EOF > /etc/bind/named.conf.options
acl "trusted" {
    $NETWORK_CIDR;
    localhost;
};

options {
    directory "/var/cache/bind";
    recursion yes;
    allow-query { trusted; };
    listen-on { any; };
    allow-transfer { none; };
    forwarders {
        1.1.1.1;
        8.8.8.8;
    };
};
EOF
