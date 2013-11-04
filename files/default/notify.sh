#!/usr/bin/env bash

action=$1
iface=$2
vip=$3
src=$4

# Idempotently make sure namespace/veth/sysctls are setup
ip netns add vips
ip link add vip-br type veth peer name vip-ns netns vips
ip link set vip-br up
ip netns exec vips ip link set vip-ns up
sysctl net.ipv4.conf.${iface}.proxy_arp=1
sysctl net.ipv4.conf.vip-br.proxy_arp=1
sysctl net.ipv4.conf.lo.arp_ignore=1
sysctl net.ipv4.conf.lo.arp_announce=2

case $action in
  add)
    ip route add $vip/32 dev vip-br src $src
    ip netns exec vips iptables -t nat -A PREROUTING -d $vip/32 -j DNAT --to-dest $src
    ip netns exec vips iptables -t nat -A POSTROUTING -m conntrack --ctstate DNAT --ctorigdst $vip/32 -j SNAT --to-source $vip
    ip netns exec vips ip addr add $vip/32 dev vip-ns
    ip netns exec vips ip route add default dev vip-ns
    ;;
  haproxy)
    ip addr add $vip/32 dev lo
    ip netns exec vips ip addr add $vip/32 dev vip-ns
    ip netns exec vips ip route add default dev vip-ns
    ;; 
  del)
    ip route del $vip/32 dev vip-br src $src
    ip addr del $vip/32 dev lo
    ip netns exec vips ip addr del $vip/32 dev vip-ns
    ip netns exec vips iptables -t nat -D PREROUTING -d $vip/32 -j DNAT --to-dest $src
    ip netns exec vips iptables -t nat -D POSTROUTING -m conntrack --ctstate DNAT --ctorigdst $vip/32 -j SNAT --to-source $vip
    ;;
esac
