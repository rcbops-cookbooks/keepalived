#!/usr/bin/env bash

# Helper functions
_log() { if [[ -n "$1" ]]; then logger -t update_route "$2" "$1"; fi; }

_exit() {
  if [[ -n "$1" ]]; then
    if [[ $2 ]]; then
      _log "$1" "-s"
    else
      _log "$1"
    fi
  fi
  exit 1
}

_errexit() { _exit "$1" 1; }

_help() { _errexit "Error updating route. Usage: update_route ACTION VIP LOCAL_IP"; }

# Grab args
action=$1
vip=$2

# Check args
if [[ $# -lt 2 ]] || [[ -z $action ]] || [[ -z $vip ]]; then _help; fi

# Try to snag VIP interface
iface=$(ip r sh table local $vip 2>/dev/null | cut -d' ' -f4)

# Didn't find it?
if [[ -z $iface ]]; then _errexit "Invalid VIP $vip! VIP must exist on an interface."; fi

# Grab primary IP on interface
src=$(ip -o -4 a sh $iface primary | sed -nr '1 s/^.*inet ([^/]*).*$/\1/p')

# Check it
if [[ -z $src ]]; then _errexit "No IP found on $iface. Expected at least $vip."; fi
if [[ $src == $vip ]]; then _errexit "Primary IP $src on $iface is VIP. A non-VIP primary IP must exist."; fi

_add_nat_rules() {
  iptables -t nat -I PREROUTING 1 -d $vip/32 -j DNAT --to-destination $src
  iptables -t nat -I OUTPUT 1 -d $vip/32 -o lo -j DNAT --to-destination $src
}

_rm_nat_rules() {
  iptables -t nat -D PREROUTING -d $vip/32 -j DNAT --to-destination $src
  iptables -t nat -D OUTPUT -d $vip/32 -o lo -j DNAT --to-destination $src
}

# Do the things
case $action in
  "add")
    _log "Merging local route for $vip with source $src."
    ip r r table local local $vip dev $iface src $src # Replace
    _rm_nat_rules
    _add_nat_rules
    ;;
  "del")
    _log "Deleting local route for $vip with source $src."
    ip r d table local local $vip dev $iface src $src # Delete
    conntrack -D -d $vip
    _rm_nat_rules
    ;;
  *)
    _help
esac

exit 0 # Success!
