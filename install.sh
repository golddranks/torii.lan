#!/bin/sh -eu

CURRENT_IP=${1:-192.168.1.1}

[ ! -d "../certs" ] && echo "Prepare ../certs directory" && exit 1
[ ! -d "../pubkeys" ] && echo "Prepare ../pubkeys directory" && exit 1

. ./secrets.sh
SSH_PUBKEY=$(cat $HOME/.ssh/id_rsa.pub)

# Dropping the host key using SCP because the dropbear format is a binary format
echo "$DROPBEAR_HOST_KEY" | base64 --decode > dropbear_ed25519_host_key
scp -o StrictHostKeyChecking=no dropbear_ed25519_host_key \
    "root@${CURRENT_IP}:/etc/dropbear/dropbear_ed25519_host_key"
rm dropbear_ed25519_host_key
ssh -o StrictHostKeyChecking=no "root@${CURRENT_IP}" "/etc/init.d/dropbear restart"

echo "Dropbear restarted."
ssh-keygen -R "${CURRENT_IP}"

# x509 certs for the admin panel are also unwieldy to handle so let's SCP them
ssh -o StrictHostKeyChecking=no "root@${CURRENT_IP}" "mkdir -p /etc/ssl"
scp ../certs/cert/torii.lan.key "root@${CURRENT_IP}:/etc/ssl/torii.lan.key"
scp ../certs/cert/torii.lan.chain.pem "root@${CURRENT_IP}:/etc/ssl/torii.lan.chain.pem"

# Sending the install scripts
scp remote.sh "root@${CURRENT_IP}:"
scp ../pubkeys/authorized_keys_strict "root@${CURRENT_IP}:"
ssh "root@${CURRENT_IP}" "./remote.sh '$ROOT_PW' '$SSH_PUBKEY' '$WIFI_PW' '$WG_KEY' '$WG_PRESHARED_KEY'"
echo "Booting."
ssh "root@${CURRENT_IP}" "reboot now"