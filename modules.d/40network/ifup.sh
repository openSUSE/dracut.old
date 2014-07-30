#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh
#
# We don't need to check for ip= errors here, that is handled by the
# cmdline parser script
#
# without $2 means this is for real netroot case
# or it is for manually bring up network ie. for kdump scp vmcore
PATH=/usr/sbin:/usr/bin:/sbin:/bin

type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh
type ip_to_var >/dev/null 2>&1 || . /lib/net-lib.sh

# Huh? No $1?
[ -z "$1" ] && exit 1

# $netif reads easier than $1
netif=$1
use_bridge='false'
use_vlan='false'

[ -d /var/lib/wicked ] || mkdir -p /var/lib/wicked

# enslave this interface to bond?
for i in /tmp/bond.*.info; do
    [ -e "$i" ] || continue
    unset bondslaves
    unset bondname
    . "$i"
    for slave in $bondslaves ; do
        if [ "$netif" = "$slave" ] ; then
            netif=$bondname
            break 2
        fi
    done
done

if [ -e /tmp/team.info ]; then
    . /tmp/team.info
    for slave in $teamslaves ; do
        if [ "$netif" = "$slave" ] ; then
            netif=$teammaster
        fi
    done
fi

if [ -e /tmp/vlan.info ]; then
    . /tmp/vlan.info
    if [ "$netif" = "$phydevice" ]; then
        if [ "$netif" = "$bondname" ] && [ -n "$DO_BOND_SETUP" ] ; then
            : # We need to really setup bond (recursive call)
        elif [ "$netif" = "$teammaster" ] && [ -n "$DO_TEAM_SETUP" ] ; then
            : # We need to really setup team (recursive call)
        else
            netif="$vlanname"
            use_vlan='true'
        fi
    fi
fi

# bridge this interface?
if [ -e /tmp/bridge.info ]; then
    . /tmp/bridge.info
    for ethname in $ethnames ; do
        if [ "$netif" = "$ethname" ]; then
            if [ "$netif" = "$bondname" ] && [ -n "$DO_BOND_SETUP" ] ; then
                : # We need to really setup bond (recursive call)
            elif [ "$netif" = "$teammaster" ] && [ -n "$DO_TEAM_SETUP" ] ; then
                : # We need to really setup team (recursive call)
            elif [ "$netif" = "$vlanname" ] && [ -n "$DO_VLAN_SETUP" ]; then
                : # We need to really setup vlan (recursive call)
            else
                netif="$bridgename"
                use_bridge='true'
            fi
        fi
    done
fi

# disable manual ifup while netroot is set for simplifying our logic
# in netroot case we prefer netroot to bringup $netif automaticlly
[ -n "$2" -a "$2" = "-m" ] && [ -z "$netroot" ] && manualup="$2"
[ -z "$netroot" ] && [ -z "$manualup" ] && exit 0
if [ -n "$manualup" ]; then
    >/tmp/net.$netif.manualup
else
    [ -e /tmp/net.${netif}.did-setup ] && exit 0
    [ -e /sys/class/net/$netif/address ] && \
        [ -e /tmp/net.$(cat /sys/class/net/$netif/address).did-setup ] && exit 0
fi

dhcp_apply() {
    if [ -f /tmp/leaseinfo.${netif}.dhcp.ipv${1:1:1} ]; then
        . /tmp/leaseinfo.${netif}.dhcp.ipv${1:1:1}
    else
        warn "DHCP failed";
        return 1
    fi

    if [ -z "${IPADDR}" ] || [ -z "${INTERFACE}" ]; then
           warn "Missing crucial DHCP variables"
           return 1
    fi

    # Assign IP address
    ip $1 addr add "$IPADDR" ${BROADCAST:+broadcast $BROADCAST} dev "$INTERFACE"

    # Assign network route the interface is attached to
    if [ -n "${NETWORK}" ]; then
        ip $1 route add "$NETWORK"/"$PREFIXLEN" dev "$INTERFACE"
    fi

    # Assign provided routes
    local r route=()
    if [ -n "${ROUTES}" ]; then
        for r in ${ROUTES}; do
            route=(${r//,/ })
            ip $1 route add "$route[0]"/"$route[1]" via "$route[2]" dev "$INTERFACE"
        done
    fi

    # Assign provided routers
    local g
    if [ -n "${GATEWAYS}" ]; then
        for g in ${GATEWAYS}; do
            ip $1 route add default via "$g" dev "$INTERFACE" && break
        done
    fi

    # Setup hostname
    [ -n "${HOSTNAME}" ] && hostname "$HOSTNAME"

    # If nameserver= has not been specified, use what dhcp provides
    if [ ! -s /tmp/net.$netif.resolv.conf ]; then
        if [ -n "${DNSDOMAIN}" ]; then
            echo domain "${DNSDOMAIN}"
        fi >> /tmp/net.$netif.resolv.conf

        if [ -n "${DNSSEARCH}" ]; then
            echo search "${DNSSEARCH}"
        fi >> /tmp/net.$netif.resolv.conf

        if  [ -n "${DNSSERVERS}" ] ; then
            for s in ${DNSSERVERS}; do
                echo nameserver "$s"
            done
        fi >> /tmp/net.$netif.resolv.conf
    fi
    [ -e /tmp/net.$netif.resolv.conf ] && \
        cp -f /tmp/net.$netif.resolv.conf /etc/resolv.conf

    info "DHCP is finished successfully"
    return 0
}

# Run dhclient
do_dhcp() {
    # dhclient-script will mark the netif up and generate the online
    # event for nfsroot
    # XXX add -V vendor class and option parsing per kernel

    [ -f /tmp/leaseinfo.${netif}.dhcp.ipv${1:1:1} ] && return 0

    info "Preparation for DHCP transaction"

    local dhclient=''
    if [ "$1" = "-4" ] ; then
        dhclient="wickedd-dhcp4"
    elif [ "$1" = "-6" ] ; then
        dhclient="wickedd-dhcp6"
    fi

    # Address changed
    ip $1 addr flush dev "$netif"

    if ! iface_has_link $netif; then
        warn "No carrier detected"
        warn "Trying to set $netif up..."
        ip $1 link set dev "$netif" up
        if ! iface_has_link $netif; then
            warn "Failed..."
            return 1
        fi
    fi

    echo "Starting dhcp for interface $netif"
    $dhclient --test $netif > /tmp/leaseinfo.${netif}.dhcp.ipv${1:1:1}
    dhcp_apply $1 || return $?

    echo $netif > /tmp/net.${netif}.did-setup
    echo $netif > /tmp/setup_net_${netif}.ok
    return 0
}

load_ipv6() {
    modprobe ipv6
    i=0
    while [ ! -d /proc/sys/net/ipv6 ]; do
        i=$(($i+1))
        [ $i -gt 10 ] && break
        sleep 0.1
    done
}

do_ipv6auto() {
    load_ipv6
    echo 0 > /proc/sys/net/ipv6/conf/$netif/forwarding
    echo 1 > /proc/sys/net/ipv6/conf/$netif/accept_ra
    echo 1 > /proc/sys/net/ipv6/conf/$netif/accept_redirects
    linkup $netif
    wait_for_ipv6_auto $netif

    [ -n "$hostname" ] && echo "echo $hostname > /proc/sys/kernel/hostname" > /tmp/net.$netif.hostname

    return 0
}

# Handle static ip configuration
do_static() {
    strglobin $ip '*:*:*' && load_ipv6

    linkup $netif
    [ -n "$macaddr" ] && ip link set address $macaddr dev $netif
    [ -n "$mtu" ] && ip link set mtu $mtu dev $netif
    [ -n "$mask" -a -z "$prefix" ] && prefix=$(mask_to_prefix $mask)
    if [ "${ip##*/}" != "${ip}" ] ; then
        prefix="${ip##*/}"
        ip="${ip%/*}"
    fi
    if strglobin $ip '*:*:*'; then
        # Always assume /64 prefix for IPv6
        [ -z "$prefix" ] && prefix=64
        # note no ip addr flush for ipv6
        ip addr add $ip/$prefix ${srv:+peer $srv} dev $netif
        wait_for_ipv6_dad $netif
    else
        # Assume /24 prefix for IPv4
        [ -z "$prefix" ] && prefix=24
        ip addr flush dev $netif
        ip addr add $ip/$prefix ${srv:+peer $srv} brd + dev $netif
    fi

    [ -n "$gw" ] && echo ip route add default via $gw dev $netif > /tmp/net.$netif.gw
    [ -n "$hostname" ] && echo "echo $hostname > /proc/sys/kernel/hostname" > /tmp/net.$netif.hostname

    return 0
}

# loopback is always handled the same way
if [ "$netif" = "lo" ] ; then
    ip link set lo up
    ip addr add 127.0.0.1/8 dev lo
    exit 0
fi

# start bond if needed
if [ -e /tmp/bond.${netif}.info ]; then
    . /tmp/bond.${netif}.info

    if [ "$netif" = "$bondname" ] && [ ! -e /tmp/net.$bondname.up ] ; then # We are master bond device
        modprobe bonding
        echo "+$netif" >  /sys/class/net/bonding_masters
        ip link set $netif down

        # Stolen from ifup-eth
        # add the bits to setup driver parameters here
        for arg in $bondoptions ; do
            key=${arg%%=*};
            value=${arg##*=};
            # %{value:0:1} is replaced with non-bash specific construct
            if [ "${key}" = "arp_ip_target" -a "${#value}" != "0" -a "+${value%%+*}" != "+" ]; then
                OLDIFS=$IFS;
                IFS=',';
                for arp_ip in $value; do
                    echo +$arp_ip > /sys/class/net/${netif}/bonding/$key
                done
                IFS=$OLDIFS;
            else
                echo $value > /sys/class/net/${netif}/bonding/$key
            fi
        done

        linkup $netif

        for slave in $bondslaves ; do
            ip link set $slave down
            echo "+$slave" > /sys/class/net/$bondname/bonding/slaves
            linkup $slave
        done

        # add the bits to setup the needed post enslavement parameters
        for arg in $BONDING_OPTS ; do
            key=${arg%%=*};
            value=${arg##*=};
            if [ "${key}" = "primary" ]; then
                echo $value > /sys/class/net/${netif}/bonding/$key
            fi
        done
    fi
fi

if [ -e /tmp/team.info ]; then
    . /tmp/team.info
    if [ "$netif" = "$teammaster" ] && [ ! -e /tmp/net.$teammaster.up ] ; then
        # We shall only bring up those _can_ come up
        # in case of some slave is gone in active-backup mode
        working_slaves=""
        for slave in $teamslaves ; do
            ip link set $slave up 2>/dev/null
            if wait_for_if_up $slave; then
                working_slaves+="$slave "
            fi
        done
        # Do not add slaves now
        teamd -d -U -n -t $teammaster -f /etc/teamd/$teammaster.conf
        for slave in $working_slaves; do
            # team requires the slaves to be down before joining team
            ip link set $slave down
            teamdctl $teammaster port add $slave
        done
        ip link set $teammaster up
    fi
fi

if [ -e /tmp/bridge.info ]; then
    . /tmp/bridge.info
# start bridge if necessary
    if [ "$netif" = "$bridgename" ] && [ ! -e /tmp/net.$bridgename.up ]; then
        brctl addbr $bridgename
        brctl setfd $bridgename 0
        for ethname in $ethnames ; do
            if [ "$ethname" = "$bondname" ] ; then
                DO_BOND_SETUP=yes ifup $bondname -m
            elif [ "$ethname" = "$teammaster" ] ; then
                DO_TEAM_SETUP=yes ifup $teammaster -m
            elif [ "$ethname" = "$vlanname" ]; then
                DO_VLAN_SETUP=yes ifup $vlanname -m
            else
                linkup $ethname
            fi
            brctl addif $bridgename $ethname
        done
    fi
fi

get_vid() {
    case "$1" in
    vlan*)
        echo ${1#vlan}
        ;;
    *.*)
        echo ${1##*.}
        ;;
    esac
}

if [ "$netif" = "$vlanname" ] && [ ! -e /tmp/net.$vlanname.up ]; then
    modprobe 8021q
    if [ "$phydevice" = "$bondname" ] ; then
        DO_BOND_SETUP=yes ifup $phydevice -m
    elif [ "$phydevice" = "$teammaster" ] ; then
        DO_TEAM_SETUP=yes ifup $phydevice -m
    else
        linkup "$phydevice"
    fi
    ip link add dev "$vlanname" link "$phydevice" type vlan id "$(get_vid $vlanname)"
    ip link set "$vlanname" up
fi

# No ip lines default to dhcp
ip=$(getarg ip)

if [ -z "$ip" ]; then
    namesrv=$(getargs nameserver)
    for s in $namesrv; do
        echo nameserver $s >> /tmp/net.$netif.resolv.conf
    done

    if [ "$netroot" = "dhcp6" ]; then
        do_dhcp -6
    else
        do_dhcp -4
    fi
fi


# Specific configuration, spin through the kernel command line
# looking for ip= lines
for p in $(getargs ip=); do
    ip_to_var $p
    # skip ibft
    [ "$autoconf" = "ibft" ] && continue

    case "$dev" in
        ??:??:??:??:??:??)  # MAC address
            _dev=$(iface_for_mac $dev)
            [ -n "$_dev" ] && dev="$_dev"
            ;;
        ??-??-??-??-??-??)  # MAC address in BOOTIF form
            _dev=$(iface_for_mac $(fix_bootif $dev))
            [ -n "$_dev" ] && dev="$_dev"
            ;;
    esac

    # If this option isn't directed at our interface, skip it
    [ -n "$dev" ] && [ "$dev" != "$netif" ] && \
    [ "$use_bridge" != 'true' ] && \
    [ "$use_vlan" != 'true' ] && continue

    if [ "$autoconf" = "static" ] &&
        [ -e /etc/sysconfig/network/ifcfg-${netif} ] ; then
        # Pull in existing static configuration
        . /etc/sysconfig/network/ifcfg-${netif}
        ip=${IPADDR}
        prefix=${PREFIXLEN}
        mtu=${MTU}
        server=${REMOTE_IPADDR}
        gw=${GATEWAY}
        autoconf=${BOOTPROTO}
    fi

    # setup nameserver
    namesrv="$dns1 $dns2 $(getargs nameserver)"
    for s in $namesrv; do
        echo nameserver $s >> /tmp/net.$netif.resolv.conf
    done

    # Store config for later use
    for i in ip srv gw mask prefix hostname macaddr dns1 dns2; do
        eval '[ "$'$i'" ] && echo '$i'="$'$i'"'
    done > /tmp/net.$netif.override

    case $autoconf in
        dhcp4|dhcp|on|any)
            do_dhcp -4 ;;
        dhcp6)
            load_ipv6
            do_dhcp -6 ;;
        auto6)
            do_ipv6auto ;;
        *)
            do_static ;;
    esac

    if [ $? -eq 0 ]; then
        > /tmp/net.${netif}.up

        setup_net $netif
        source_hook initqueue/online $netif
        if [ -z "$manualup" ]; then
            /sbin/netroot $netif
        fi
    fi

    exit 0
done

# netif isn't the top stack? Then we should exit here.
# eg. netif is bond0. br0 is on top of it. dhcp br0 is correct but dhcp
#     bond0 doesn't make sense.
if [ -n "$DO_BOND_SETUP" -o -n "$DO_TEAM_SETUP" -o -n "$DO_VLAN_SETUP" ]; then
    exit 0
fi

# no ip option directed at our interface?
if [ ! -e /tmp/net.${netif}.up ]; then
    if getargs 'ip=dhcp6'; then
        load_ipv6
        do_dhcp -6
    else
        do_dhcp -4
    fi
fi

exit 0
