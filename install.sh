#!/bin/bash


## Save status of this script to a file in case it
## needs to be restarted.

status_file="/home/ec2-user/install_status.txt"

servername_file="/home/ec2-user/install_servername.txt"
serverip_file="/home/ec2-user/install_serverip.txt"
iprange_file="/home/ec2-user/install_iprange.txt"

# Read the last successful step from the status file
last_step=$(cat "$status_file")


# Function for Step 1
step1() {

    echo ""
    echo "##"
    echo "## Installing openvpn and easy-rsa... "
    echo "## Location:  /etc/openvpn"
    echo "##"
    echo "## Press enter to continue... "
    read nothing


    wget https://swupdate.openvpn.org/community/releases/openvpn-2.6.3.tar.gz
    tar xvf openvpn-2.6.3.tar.gz

    dnf install -y gcc make
    dnf -y install libnl3-devel.aarch64
    dnf -y install libcap-ng-devel.aarch64
    dnf -y install openssl-devel.aarch64
    dnf -y install lz4.aarch64
    dnf -y install lz4-devel.aarch64
    dnf -y install openssl-devel.aarch64
    dnf -y install openssl.aarch64
    dnf -y install openssl-libs.aarch64
    dnf install -y lzo.aarch64 lzo-devel.aarch64
    dnf -y install pam.aarch64 pam-devel.aarch64

    # jq needed for this script
    dnf -y install jq

    # Save the successful step to the status file
    echo "1" > "$status_file"
    
    step2
}

# Function for Step 2
step2() {

    cd openvpn-2.6.3
    ./configure
    make
    make install

    cd ..

    mv openvpn-2.6.3 /etc/openvpn
    cd /etc/openvpn

    wget https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.2/EasyRSA-3.1.2.tgz
    tar xvf EasyRSA-3.1.2.tgz
    mv EasyRSA-3.1.2/ easy-rsa/; rm -f EasyRSA-3.1.2.tgz

    cd easy-rsa
    mkdir pki
    
    ./easyrsa init-pki

cat > /etc/openvpn/pki/vars << EOF
set_var EASYRSA                 "$PWD"
set_var EASYRSA_PKI             "$EASYRSA/pki"
set_var EASYRSA_DN              "cn_only"
set_var EASYRSA_REQ_COUNTRY     "US"
set_var EASYRSA_REQ_PROVINCE    "CA"
set_var EASYRSA_REQ_CITY        "San Francisco"
set_var EASYRSA_REQ_ORG         "EFW CERTIFICATE AUTHORITY"
set_var EASYRSA_REQ_EMAIL       "openvpn@db101.org"
set_var EASYRSA_REQ_OU          "EFW EASY CA"
set_var EASYRSA_KEY_SIZE        2048
set_var EASYRSA_ALGO            rsa
set_var EASYRSA_CA_EXPIRE       7500
set_var EASYRSA_CERT_EXPIRE     3650
set_var EASYRSA_NS_SUPPORT      "no"
set_var EASYRSA_NS_COMMENT      "EFW CERTIFICATE AUTHORITY"
set_var EASYRSA_EXT_DIR         "$EASYRSA/x509-types"
set_var EASYRSA_SSL_CONF        "$EASYRSA/openssl-easyrsa.cnf"
set_var EASYRSA_DIGEST          "sha256"
EOF

    chmod +x pki/vars

    # Save the successful step to the status file
    echo "2" > "$status_file"
    step3
}

# Function for Step 3
step3() {

if [ -f "$servername_file" ]; then
    if [ -z "$servername" ]; then
        # Set the variable from the contents of a file
        servername=$(cat $servername_file)
    fi
else
    echo ""
    echo "## What is the name of this server? (ex: efw-vpn-vpc-01) "
    read servername
    echo "$servername" > "$servername_file"
fi



if [ -f "$serverip_file" ]; then
    if [ -z "$serverip" ]; then
        # Set the variable from the contents of a file
        serverip=$(cat $serverip_file)
    fi
else
    echo "##"
    echo "## What is the elastic ip (public ip) address of this server? (ex: 13.52.49.251) "
    read serverip
    echo "$serverip" > "$serverip_file"
fi

if [ -f "$iprange_file" ]; then
    if [ -z "$iprange" ]; then
        # Set the variable from the contents of a file
        iprange=$(cat $iprange_file)
    fi
else
    echo "##"
    echo "## What is the ip range (whats the starting ip to assign to clients)? (ex: 10.1.10.0) "
    read iprange
    echo "$iprange" > "$iprange_file"
fi



    echo "##"
    echo "## Uploading passphrase and connection details to aws secrets manager." 
    echo "##"
    echo "## Secret name: $servername"
    echo "##"
    echo "## Please paste the *.pem key you were given when you created this instance into this new secret."
    echo "##"


    # Create a password for openvpn on this server
    passphrase=$(cat /dev/urandom | tr -dc a-zA-Z0-9 | fold -w 14 | head -n 1)

    ## upload a secret
    secretoutput=$(aws secretsmanager create-secret --name $servername --description "key and connection details for vpn: $servername" --secret-string "{\"pem\":\"\", \"connection-command\":\"ssh -i ./$servername.pem ec2-user@$serverpublicip\", \"openVPN-passphrase\":\"$passphrase\"}")

    # Parse the output as JSON and check for the presence of a key
    if [[ $(echo "$output" | jq -e '.ARN') != "null" ]]; then
        echo "##"
        echo "## Secret was successfully saved."
        echo "##"
        echo "##"
        echo "## I created a passphrase for openvpn. You'll need to enter it on the next command."
        echo "##"
        echo "## The passphrase is:"
        echo "##"
        echo "## $passphrase"
        echo "##"
        echo "##"
        echo "## Press Enter to continue"
        echo "##"

        # Save the successful step to the status file
        echo "3" > "$status_file"
        
        step4
    else
        echo "-- Failed to upload secret."
        echo "--"
        echo "$secretoutput"
        exit 1
    fi
}

# Function for Step 4
step4() {
    echo "##"
    echo "## Building server certificates. Have your openVPN passphrase ready." 
    echo "##"
    
    cd /etc/openvpn/easy-rsa
    
    # Check if the variable is empty or unset
    if [ -z "$servername" ]; then
        # Set the variable from the contents of a file
        servername=$(cat $servername_file)
    fi


    ./easyrsa build-ca


    ./easyrsa gen-req $servername nopass

    ./easyrsa sign-req server $servername

    ./easyrsa gen-dh


cat > /etc/openvpn/server.conf << EOF

port 11094
proto udp
dev tun


ca /etc/openvpn/easy-rsa/pki/ca.crt
cert /etc/openvpn/easy-rsa/pki/issued/$servername.crt
key /etc/openvpn/easy-rsa/pki/private/$servername.key  # This file should be kept secret
dh /etc/openvpn/easy-rsa/pki/dh.pem

topology subnet

# Network Configuration - Internal network
# Redirect all Connection through OpenVPN Server
push "redirect-gateway def1"

# Using the DNS from https://dns.watch
push "dhcp-option DNS 84.200.69.80"
push "dhcp-option DNS 84.200.70.40"

#Enable multiple client to connect with same Certificate key
duplicate-cn

# TLS Security
cipher AES-256-CBC
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256:TLS-DHE-RSA-WITH-AES-128-GCM-SHA256:TLS-DHE-RSA-WITH-AES-128-CBC-SHA256
auth SHA512
auth-nocache

# Other Configuration
keepalive 10 120
persist-key
persist-tun
#comp-lzo yes
#allow-compression yes
daemon
user nobody
group nobody

# OpenVPN Log
log-append /var/log/openvpn.log
verb 3

# write status to file every minute
status openvpn-status.log


# Configure server mode and supply a VPN subnet
# for OpenVPN to draw client addresses from.
# The server will take x.x.x.1 for itself,
# the rest will be made available to clients.
# Each client will be able to reach the server
# on x.x.x.1.

server $iprange 255.255.255.0

# Maintain a record of client <-> virtual IP address
# associations in this file.  If OpenVPN goes down or
# is restarted, reconnecting clients can be assigned
# the same virtual IP address from the pool that was
# previously assigned.

ifconfig-pool-persist ipp.txt

explicit-exit-notify 1

EOF





    echo "##"
    echo "##"
    echo "## Installing iptables / firewall."
    echo "##"
    echo ""

    dnf -y install iptables


cat > /home/ec2-user/start_vpn.sh << EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          openvpn
# Required-Start:
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: openvpn
# Description:       openvpn
### END INIT INFO



# Flushing all rules
iptables -F
iptables -X
# Forward inbound tunnel traffic from vpn pool network
iptables -t nat -A POSTROUTING -s $iprange/24 -o ens5 -j MASQUERADE
# Allow unlimited traffic on loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
# Allow SSH traffic:
iptables -A INPUT -i ens5 -m state --state NEW,ESTABLISHED -p tcp --dport 22 -j ACCEPT
# Allow UDP traffic on port 11094:
iptables -A INPUT -i ens5 -m state --state NEW,ESTABLISHED -p udp --dport 11094 -j ACCEPT
# Allow TUN interface connections to OpenVPN server:
iptables -A INPUT -i tun+ -j ACCEPT
# Allow TUN interface connections to be forwarded through other interfaces:
iptables -A FORWARD -i tun+ -j ACCEPT
iptables -A FORWARD -i tun+ -o ens5 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i ens5 -o tun+ -m state --state RELATED,ESTABLISHED -j ACCEPT
# Allow output:  
iptables -A OUTPUT -o tun+ -j ACCEPT
# Make sure nothing else comes or goes out of this box
#iptables -A INPUT -j DROP

# enable routing
sysctl -w net.ipv4.ip_forward=1

# Start server
openvpn --config /etc/openvpn/server.conf

EOF


    # Run on startup 

    mv /home/ec2-user/start_vpn.sh /etc/init.d/start_vpn.sh
    chmod +x /etc/init.d/start_vpn.sh
    ln -s /etc/init.d/start_vpn.sh /etc/rc.d/rc3.d/S99start_vpn
    
    echo "##"
    echo "##"
    echo "## All done! You can create a client now."
    echo "##"
    echo ""


    # Save the successful step to the status file
    echo "4" > "$status_file"
    step5
}

# If all install steps are done, keep making clients
# Function for Step 5
step5() {

    cd /etc/openvpn/easy-rsa
    
    # Check if the variable is empty or unset
    if [ -z "$servername" ]; then
        # Set the variable from the contents of a file
        servername=$(cat $servername_file)
    fi

    # Check if the variable is empty or unset
    if [ -z "$serverip" ]; then
        # Set the variable from the contents of a file
        serverip=$(cat $serverip_file)
    fi

    # Check if the variable is empty or unset
    if [ -z "$iprange" ]; then
        # Set the variable from the contents of a file
        iprange=$(cat $iprange_file)
    fi

    echo "##"
    echo "## Username for this client? "
    read clientname
    echo "##"
    
    ./easyrsa gen-req $clientname nopass
    ./easyrsa sign-req client $clientname
    
    
    # Build client ovpn config file
cat > $clientname-$servername.ovpn << EOF
client
dev tun
remote $serverip 11094
proto udp
resolv-retry infinite
nobind
remote-cert-tls server
persist-key
persist-tun
<ca>
EOF
cat pki/ca.crt >> $clientname-$servername.ovpn
cat >> $clientname-$servername.ovpn << EOF
</ca>
<cert>
EOF
cat pki/issued/$clientname.crt >> $clientname-$servername.ovpn 
cat >> $clientname-$servername.ovpn << EOF
</cert>
<key>
EOF
cat pki/private/$clientname.key >> $clientname-$servername.ovpn 
cat >> $clientname-$servername.ovpn << EOF
</key>
cipher AES-256-GCM
verb 3
EOF



## upload the new client config file to secrets manager
secretoutput=$(aws secretsmanager create-secret --name $servername-$clientname --description "vpn client configuration" --secret-string "file:///etc/openvpn/easy-rsa/$clientname-$servername.ovpn")

# Parse the output as JSON and check for the presence of a key
if [[ $(echo "$output" | jq -e '.ARN') != "null" ]]; then
    echo "## Secret was successfully saved."
else
    echo "-- Failed to upload secret."
    echo "--"
    echo ""
fi

}

# Determine the next step based on the last successful step
case "$last_step" in
    1) step2 ;;
    2) step3 ;;
    3) step4 ;;
    4) step5 ;;
    *) step1 ;;  # Start from the beginning if status file is empty or invalid
esac
