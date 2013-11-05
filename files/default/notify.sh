#!/usr/bin/env bash

action=$1
iface=$2
vip=$3
src=$4

# Idempotently make sure namespace/veth/sysctls are setup
logger -t keepalived-notify-$action "Ensuring namespace, veth pair and sysctls"
ip netns add vips
ip link add vip-br type veth peer name vip-ns netns vips
ip link set vip-br up
ip route add 169.254.123.45/32 dev vip-br
ip netns exec vips ip link set lo up
ip netns exec vips ip link set vip-ns up
ip netns exec vips ip addr add 169.254.123.45/16 dev vip-ns
ip netns exec vips sysctl net.ipv4.ip_forward=1
sysctl net.ipv4.conf.${iface}.proxy_arp=1
sysctl net.ipv4.conf.vip-br.proxy_arp=1
sysctl net.ipv4.conf.lo.arp_ignore=1
sysctl net.ipv4.conf.lo.arp_announce=2
sysctl net.ipv4.ip_forward=1

case $action in
  add)
    logger -t keepalived-notify-$action "Adding VIP route for $vip"
    ip route add $vip/32 dev vip-br src $src
    logger -t keepalived-notify-$action "Adding VIP NATs to namespace for $vip"
    ip netns exec vips iptables -t nat -A PREROUTING -d $vip/32 -j DNAT --to-dest $src
    ip netns exec vips iptables -t nat -A POSTROUTING -m conntrack --ctstate DNAT --ctorigdst $vip/32 -j SNAT --to-source $vip
    logger -t keepalived-notify-$action "Adding VIP address to namespace for $vip"
    ip netns exec vips ip addr add $vip/32 dev vip-ns
    logger -t keepalived-notify-$action "Adding VIP default route to namespace for $vip"
    ip netns exec vips ip route add default dev vip-ns
    ;;
  haproxy)
    logger -t keepalived-notify-$action "Adding VIP address to lo for $vip"
    ip addr add $vip/32 dev lo
    logger -t keepalived-notify-$action "Adding VIP address to namespace for $vip"
    ip netns exec vips ip addr add $vip/32 dev vip-ns
    logger -t keepalived-notify-$action "Adding VIP default route to namespace for $vip"
    ip netns exec vips ip route add default dev vip-ns
    ;;
  del)
    logger -t keepalived-notify-$action "Deleting VIP route for $vip"
    ip route del $vip/32 dev vip-br src $src
    logger -t keepalived-notify-$action "Deleting VIP address from lo for $vip"
    ip addr del $vip/32 dev lo
    logger -t keepalived-notify-$action "Deleting VIP address from namespace for $vip"
    ip netns exec vips ip addr del $vip/32 dev vip-ns
    logger -t keepalived-notify-$action "Deleting VIP NATs from namespace for $vip"
    ip netns exec vips iptables -t nat -D PREROUTING -d $vip/32 -j DNAT --to-dest $src
    ip netns exec vips iptables -t nat -D POSTROUTING -m conntrack --ctstate DNAT --ctorigdst $vip/32 -j SNAT --to-source $vip
    ;;
esac
