#!/bin/sh

# Based on http://xmodulo.com/how-to-install-and-configure-tinc-vpn.html

set -ex

host=$1
interface=$2
tincIP=$3
tincName=${4:-$1}

if [ ! "$1" ]; then echo "host is required as argument #1"; exit 1; fi
if [ ! "$2" ]; then echo "network interface is required as argument #2"; exit 1; fi
if [ ! "$3" ]; then echo "IP-address required as argument #3"; exit 1; fi

vpnName=scaleway
tincPath=/etc/tinc/$vpnName

myTincIP=$(ip addr show tun0 | grep -o 'inet [^/]*' | cut -d' ' -f 2)
myIP=$(ip addr show $interface | grep -o 'inet [^/]*' | cut -d' ' -f 2)
myName=$(cat $tincPath/tinc.conf | awk '/Name/ { print $3}')

rsync -Pavvzessh /var/cache/apt/archives/tinc_*.deb root@${host}:/tmp

remoteScriptFile=$(mktemp)
chmod +x $remoteScriptFile
cat <<EOF > $remoteScriptFile
#!/bin/bash
dpkg -l tinc > /dev/null || dpkg -i /tmp/tinc_*.deb
systemctl enable tinc
systemctl restart tinc
mkdir -p ${tincPath}/hosts
if [ ! -f ${tincPath}/tinc.conf ]; then
	cat <<END > ${tincPath}/tinc.conf
Name = ${tincName}
AddressFamily = ipv4
Interface = tun0
ConnectTo = ${myName}
END
fi
if [ ! -f ${tincPath}/hosts/${tincName} ]; then
	cat <<END > ${tincPath}/hosts/${tincName}
Subnet = ${tincIP}/32
END
	tincd -n $vpnName -K4096
fi

cat <<'END' > ${tincPath}/tinc-up
#!/bin/sh
ifconfig INTERFACE ${tincIP} netmask 255.255.255.0
END

cat <<'END' > ${tincPath}/tinc-down
#!/bin/sh
ifconfig INTERFACE down
END

chmod +x ${tincPath}/tinc-{up,down}
modprobe tun
EOF
sed -i -e 's/INTERFACE/$INTERFACE/g' $remoteScriptFile
scp $remoteScriptFile root@$host:~/setup-tinc.sh
ssh root@$host 'bash -x ~/setup-tinc.sh'

rsync -Pavvzessh ${tincPath}/hosts/$myName $host:${tincPath}/hosts/
rsync -Pavvzessh $host:${tincPath}/hosts/${tincName} ${tincPath}/hosts/
tincd -n $vpnName -k HUP || tincd -n $vpnName

ssh root@$host "tincd -n $vpnName -k HUP || tincd -n $vpnName"

routeScriptFile=$(mktemp)
chmod +x $routeScriptFile
cat <<EOF > $routeScriptFile
#!/bin/bash
tincd -n $vpnName -k HUP || tincd -n $vpnName
GATEWAY=\$(route -n | grep '^0.0.0.0' | awk '{print \$2}')
route add -host $myIP gw \$GATEWAY
route add default gw $myTincIP
route del default gw \$GATEWAY
EOF
scp $routeScriptFile root@$host:~/setup-default-gw.sh
ssh root@$host 'bash -x ~/setup-default-gw.sh'