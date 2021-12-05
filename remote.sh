#!/bin/sh -eu

ROOT_PW=${1:?}
SSH_PUBKEY=${2:?}
WIFI_PW=${3:?}
WG_KEY=${4:?}
WG_PRESHARED_KEY=${5:?}

. /etc/openwrt_release

echo "Setting up config on TP-Link Archer C7 v2.0/JP. OS: $DISTRIB_DESCRIPTION"

# Add the host pubkey of the installer host
echo "$SSH_PUBKEY" > /etc/dropbear/authorized_keys

# For convenience, add other common pubkeys
cat authorized_keys_strict >> /etc/dropbear/authorized_keys
rm authorized_keys_strict

passwd << EOF
$ROOT_PW
$ROOT_PW
EOF

uci set dropbear.cfg014dd4.RootPasswordAuth='off'
uci set dropbear.cfg014dd4.PasswordAuth='off'
uci set dropbear.cfg014dd4.Interface='lan'
uci commit dropbear

echo "Security config done."


# Lan
uci set network.lan.ipaddr='10.0.33.1'
uci set network.globals.ula_prefix=''
uci commit network

# Wifi
uci set wireless.default_radio0.ssid='Torii'
uci set wireless.default_radio0.key="$WIFI_PW"
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.country='JP'
uci set wireless.radio1.disabled='1'
uci commit wireless

# General system settings
uci set system.cfg01e48a.hostname='torii'
uci set system.cfg01e48a.timezone='JST-9'
uci set system.cfg01e48a.zonename='Asia/Tokyo'
uci commit system

echo "Basic network config done."

echo "Start installing external packages."

opkg update

echo "Updated package list."

opkg install curl nano coreutils-base64 wget bind-dig tcpdump ip-full diffutils

echo "Utilities installed."


# Install nginx to support performant HTTPS admin panel
opkg install luci-ssl-nginx

uci delete nginx._lan.listen || true
uci add_list nginx._lan.listen='666 ssl default_server'
uci add_list nginx._lan.listen='[::]:666 ssl default_server'
uci set nginx._lan.ssl_certificate='/etc/ssl/torii.lan.chain.pem'
uci set nginx._lan.ssl_certificate_key='/etc/ssl/torii.lan.key'

uci commit nginx

echo "HTTPS enabled on web interface."


# Set up Wireguard
opkg install luci-proto-wireguard luci-app-wireguard qrencode

# wg is trusted wireguard interface
uci set network.wg=interface
uci set network.wg.proto='wireguard'
uci set network.wg.private_key="$WG_KEY"
uci set network.wg.addresses="10.0.99.3/32 2404:7a80:9621:7100::9999:3/128"
uci set network.wg.dns="10.0.0.1 2404:7a80:9621:7100::1"
uci set network.wg.listen_port='51820'

uci set network.mon=wireguard_wg
uci set network.mon.description="mon"
uci set network.mon.public_key='9hQCYRWb+5tpcee3oLK/J+wFuAZpUo5KSFkxzAGQ4R0='
uci set network.mon.preshared_key="$WG_PRESHARED_KEY"
uci set network.mon.allowed_ips="0.0.0.0/0 ::/0"
uci set network.mon.endpoint_host="drasa.eu"
uci set network.mon.endpoint_port="51820"
uci set network.mon.route_allowed_ips='1'
uci set network.mon.persistent_keepalive='25'

uci commit network

# Wireguard is untrusted zone? (Maybe it doesn't need to be though?)
uci set firewall.cfg03dc81.network='wan wan6 wg'

# Allow Wireguard port
uci set firewall.allow_wireguard=rule
uci set firewall.allow_wireguard.name='Input Wireguard'
uci set firewall.allow_wireguard.proto='udp'
uci set firewall.allow_wireguard.src='wan'
uci set firewall.allow_wireguard.dest_port='51820'
uci set firewall.allow_wireguard.target='ACCEPT'

uci commit firewall
