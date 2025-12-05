#!/bin/bash

# --- CONFIGURATION ---
# Servers network configuration
ZONE_NAME="homelab.local"
DNS_SERVER_1_IP="192.168.159.10"
DNS_VIRTUAL_IP="192.168.159.53"
# ---------------------

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

# Define the zone and point to the primary server
cat <<EOF > /etc/bind/named.conf.local
zone "$ZONE_NAME" {
    type slave;
    file "/var/cache/bind/db.$ZONE_NAME";
    masters { $DNS_SERVER_1_IP; };
};
EOF

# Restart the bind service
systemctl restart bind9

# Create the health check script to check that bind is running
cat <<EOF > /etc/keepalived/check_bind.sh
#!/bin/bash

if pidof named > /dev/null; then
    exit 0
else
    exit 1
fi
EOF

Make the health check script executable
chmod +x /etc/keepalived/check_bind.sh

# Create the keepalived configuration file
cat <<EOF > /etc/keepalived/keepalived.conf
vrrp_script check_bind {
    script "/etc/keepalived/check_bind.sh"
    interval 2
    timeout 2
    fall 2
    rise 2
    weight -30
}

vrrp_instance VI_1 {
    state BACKUP
    interface $INTERFACE
    virtual_router_id 55
    priority 80
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass dGrGtCxLBzoB5r6ekeAU
    }
    virtual_ipaddress {
        $DNS_VIRTUAL_IP/24
    }
    track_script {
        check_bind
    }
}
EOF

# Start the keepalived service
systemctl enable --now keepalived

