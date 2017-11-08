#!/bin/bash

if [ ! "$1" ]; then echo "tinc name is required as argument #1"; exit 1; fi
if [ ! "$2" ]; then echo "network interface is required as argument #2"; exit 1; fi
if [ ! "$3" ]; then echo "IP-address required as argument #3"; exit 1; fi

tincName=$1
interface=$2
tincIP=$3
vpnName=scaleway

tincPath=/etc/tinc/$vpnName
myIP=$(ip addr show $interface | grep -o 'inet [^/]*' | cut -d' ' -f 2)

dpkg -l tinc > /dev/null || apt-get install tinc
mkdir -p ${tincPath}/hosts

if [ ! -f "$tincPath/tinc.conf" ]; then
    cat <<EOF > $tincPath/tinc.conf
Name = ${tincName}
AddressFamily = ipv4
Interface = tun0
Mode = switch
EOF
fi

if [ ! -f "$tincPath/hosts/$tincName" ]; then
    cat <<EOF > $tincPath/hosts/$tincName
Address = ${myIP}
#Subnet = 0.0.0.0/0
EOF
echo "/etc/tinc/scaleway/rsa_key.priv" | tincd -n $vpnName -K4096
fi

if0=tun0
if1=${interface}

cat <<EOF > $tincPath/tinc-up
#!/bin/bash

ifconfig \$INTERFACE ${tincIP} netmask 255.255.255.0

#
# delete all existing rules.
#
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

# Always accept loopback traffic
iptables -A INPUT -i lo -j ACCEPT


# Allow established connections, and those not coming from the outside
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m state --state NEW ! -i $if1 -j ACCEPT
iptables -A FORWARD -i ${if1} -o ${if0} -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow outgoing connections from the LAN side.
iptables -A FORWARD -i ${if0} -o ${if1} -j ACCEPT

# Masquerade.
iptables -t nat -A POSTROUTING -o ${if1} -j MASQUERADE

# Don't forward from the outside to the inside.
iptables -A FORWARD -i ${if1} -o ${if1} -j REJECT

# Enable routing.
echo 1 > /proc/sys/net/ipv4/ip_forward
EOF

cat <<EOF > $tincPath/tinc-down
#!/bin/bash
ifconfig \$INTERFACE down
iptables -F
EOF

chmod +x $tincPath/tinc-{up,down}

modprobe tun
tincd -n $vpnName -k HUP || tincd -n $vpnName
