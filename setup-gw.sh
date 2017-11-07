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
EOF
fi

if [ ! -f "$tincPath/hosts/$tincName" ]; then
    cat <<EOF > $tincPath/hosts/$tincName
Address = ${myIP}
Subnet = 0.0.0.0/0
EOF
tincd -n $vpnName -K4096
fi

cat <<EOF > $tincPath/tinc-up
#!/bin/bash
ifconfig \$INTERFACE ${tincIP} netmask 255.255.255.0
EOF

cat <<EOF > $tincPath/tinc-down
#!/bin/bash
ifconfig \$INTERFACE down
EOF

chmod +x $tincPath/tinc-{up,down}

modprobe tun
tincd -n $vpnName -k HUP || tincd -n $vpnName

# And set up forwarding/nat
echo 1 > /proc/sys/net/ipv4/ip_forward
/sbin/iptables -t nat -A POSTROUTING -o $interface -j MASQUERADE
/sbin/iptables -A FORWARD -i $interface -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT
/sbin/iptables -A FORWARD -i tun0 -o $interface -j ACCEPT