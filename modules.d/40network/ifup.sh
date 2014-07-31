#!/bin/sh
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

# loopback is always handled the same way
if [ "$netif" = "lo" ] ; then
    ip link set lo up
    ip addr add 127.0.0.1/8 dev lo
    exit 0
fi

dhcp_apply() {
    unset IPADDR INTERFACE BROADCAST NETWORK PREFIXLEN ROUTES GATEWAYS HOSTNAME DNSDOMAIN DNSSEARCH DNSSERVERS
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
    if [ ! -s /tmp/net.$netif.resolv.conf.ipv${1:1:1} ]; then
        if [ -n "${DNSDOMAIN}" ]; then
            echo domain "${DNSDOMAIN}"
        fi >> /tmp/net.$netif.resolv.conf.ipv${1:1:1}

        if [ -n "${DNSSEARCH}" ]; then
            echo search "${DNSSEARCH}"
        fi >> /tmp/net.$netif.resolv.conf.ipv${1:1:1}

        if  [ -n "${DNSSERVERS}" ] ; then
            for s in ${DNSSERVERS}; do
                echo nameserver "$s"
            done
        fi >> /tmp/net.$netif.resolv.conf.ipv${1:1:1}
    fi
    # copy resolv.conf if it doesn't exist yet, modify otherwise
    if [ -e /tmp/net.$netif.resolv.conf.ipv${1:1:1} ] && [ ! -e /etc/resolv.conf ]; then
        cp -f /tmp/net.$netif.resolv.conf.ipv${1:1:1} /etc/resolv.conf
    else
        if [ -n "$(sed -n '/^search .*$/p' /etc/resolv.conf)" ]; then
            sed -i "s/\(^search .*\)$/\1 ${DNSSEARCH}/" /etc/resolv.conf
        else
            echo search ${DNSSEARCH} >> /etc/resolv.conf
        fi
        if  [ -n "${DNSSERVERS}" ] ; then
            for s in ${DNSSERVERS}; do
                echo nameserver "$s"
            done
        fi >> /etc/resolv.conf
    fi

    info "DHCP is finished successfully"
    return 0
}

# Run dhclient
do_dhcp() {
    # dhclient-script will mark the netif up and generate the online
    # event for nfsroot
    # XXX add -V vendor class and option parsing per kernel

    local _COUNT=0
    local _timeout=$(getargs rd.net.timeout.dhcp=)
    local _DHCPRETRY=$(getargs rd.net.dhcp.retry=)
    _DHCPRETRY=${_DHCPRETRY:-1}

    [ -f /tmp/leaseinfo.${netif}.dhcp.ipv${1:1:1} ] && return 0

    info "Preparation for DHCP transaction"

    local dhclient=''
    if [ "$1" = "-4" ] ; then
        dhclient="wickedd-dhcp4"
    elif [ "$1" = "-6" ] ; then
        dhclient="wickedd-dhcp6"
    fi

    if ! iface_has_carrier $netif; then
        warn "No carrier detected on interface $netif"
        warn "Trying to set $netif up..."
        ip $1 link set dev "$netif" up
        if ! iface_has_link $netif; then
            warn "Failed..."
            return 1
        fi
    fi

    $dhclient --test $netif > /tmp/leaseinfo.${netif}.dhcp.ipv${1:1:1}
    dhcp_apply $1 || return $?

    echo $netif > /tmp/setup_net_${netif}.ok
    return 0
}

load_ipv6() {
    [ -d /proc/sys/net/ipv6 ] && return
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
    if [ "$autoconf" = "static" ] &&
        [ -e /etc/sysconfig/network/ifcfg-${netif} ] ; then
        # Pull in existing static configuration
        . /etc/sysconfig/network/ifcfg-${netif}

        # loop over all configurations in ifcfg-$netif (IPADDR*) and apply
        for conf in ${!IPADDR@}; do
            ip=${!conf}
            [ -z "$ip" ] && continue
            ext=${conf#IPADDR}
            concat="PREFIXLEN$ext" && [ -n "${!concat}" ] && mtu=${!concat}
            concat="MTU$ext" && [ -n "${!concat}" ] && mtu=${!concat}
            concat="REMOTE_IPADDR$ext" && [ -n "${!concat}" ] && server=${!concat}
            concat="GATEWAY$ext" && [ -n "${!concat}" ] && gw=${!concat}
            concat="BOOTPROTO$ext" && [ -n "${!concat}" ] && autoconf=${!concat}
            do_static_setup
        done
    else
        do_static_setup
    fi

    return 0
}

do_static_setup() {
    strglobin $ip '*:*:*' && load_ipv6

    if [ -z "$dev" ] && ! iface_has_carrier "$netif"; then
        warn "No carrier detected on interface $netif"
        return 1
    elif ! linkup "$netif"; then
        warn "Could not bring interface $netif up!"
        return 1
    fi

    ip route get "$ip" | {
        read a rest
        if [ "$a" = "local" ]; then
            warn "Not assigning $ip to interface $netif, cause it is already assigned!"
            return 1
        fi
        return 0
    } || return 1

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
        if command -v arping2 >/dev/null; then
            if arping2 -q -C 1 -c 2 -I $netif -0 $ip ; then
                warn "Duplicate address detected for $ip for interface $netif."
                return 1
            fi
        else
            if ! arping -f -q -D -c 2 -I $netif $ip ; then
                warn "Duplicate address detected for $ip for interface $netif."
                return 1
            fi
        fi
        # Assume /24 prefix for IPv4
        [ -z "$prefix" ] && prefix=24
        ip addr add $ip/$prefix ${srv:+peer $srv} brd + dev $netif
    fi

    [ -n "$gw" ] && echo ip route replace default via $gw dev $netif > /tmp/net.$netif.gw

    for ifroute in /etc/sysconfig/network/ifroute-${netif} /etc/sysconfig/netwrk/routes ; do
        [ -e ${ifroute} ] || continue
        # Pull in existing routing configuration
        read ifr_dest ifr_gw ifr_mask ifr_if < ${ifroute}
        [ -z "$ifr_dest" -o -z "$ifr_gw" ] && continue
        if [ "$ifr_if" = "-" ] ; then
            echo ip route add $ifr_dest via $ifr_gw >> /tmp/net.$netif.gw
        else
            echo ip route add $ifr_dest via $ifr_gw dev $ifr_if >> /tmp/net.$netif.gw
        fi
    done

    [ -n "$hostname" ] && echo "echo $hostname > /proc/sys/kernel/hostname" > /tmp/net.$netif.hostname
}

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

# check, if we need VLAN's for this interface
if [ -z "$DO_VLAN_PHY" ] && [ -e /tmp/vlan.${netif}.phy ]; then
    NO_AUTO_DHCP=yes DO_VLAN_PHY=yes ifup "$netif"
    modprobe -b -q 8021q

    for i in /tmp/vlan.*.${netif}; do
        [ -e "$i" ] || continue
        read vlanname < "$i"
        if [ -n "$vlanname" ]; then
            linkup "$phydevice"
            ip link add dev "$vlanname" link "$phydevice" type vlan id "$(get_vid $vlanname)"
            ifup "$vlanname"
        fi
    done
    exit 0
fi

# bridge this interface?
if [ -z "$NO_BRIDGE_MASTER" ]; then
    for i in /tmp/bridge.*.info; do
        [ -e "$i" ] || continue
        unset bridgeslaves
        unset bridgename
        . "$i"
        for ethname in $bridgeslaves ; do
            [ "$netif" != "$ethname" ] && continue

            NO_BRIDGE_MASTER=yes NO_AUTO_DHCP=yes ifup $ethname
            linkup $ethname
            if [ ! -e /tmp/bridge.$bridgename.up ]; then
                brctl addbr $bridgename
                brctl setfd $bridgename 0
                > /tmp/bridge.$bridgename.up
            fi
            brctl addif $bridgename $ethname
            ifup $bridgename
            exit 0
        done
    done
fi

[ -d /var/lib/wicked ] || mkdir -p /var/lib/wicked

# enslave this interface to bond?
if [ -z "$NO_BOND_MASTER" ]; then
    for i in /tmp/bond.*.info; do
        [ -e "$i" ] || continue
        unset bondslaves
        unset bondname
        . "$i"
        for slave in $bondslaves ; do
            [ "$netif" != "$slave" ] && continue

            # already setup
            [ -e /tmp/bond.$bondname.up ] && exit 0

            # wait for all slaves to show up
            for slave in $bondslaves ; do
                # try to create the slave (maybe vlan or bridge)
                NO_BOND_MASTER=yes NO_AUTO_DHCP=yes ifup $slave

                if ! ip link show dev $slave >/dev/null 2>&1; then
                    # wait for the last slave to show up
                    exit 0
                fi
            done

            modprobe -q -b bonding
            echo "+$bondname" >  /sys/class/net/bonding_masters 2>/dev/null
            ip link set $bondname down

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
                        echo +$arp_ip > /sys/class/net/${bondname}/bonding/$key
                    done
                    IFS=$OLDIFS;
                else
                    echo $value > /sys/class/net/${bondname}/bonding/$key
                fi
            done

            linkup $bondname

            for slave in $bondslaves ; do
                cat /sys/class/net/$slave/address > /tmp/net.${bondname}.${slave}.hwaddr
                ip link set $slave down
                echo "+$slave" > /sys/class/net/$bondname/bonding/slaves
                linkup $slave
            done

            # add the bits to setup the needed post enslavement parameters
            for arg in $bondoptions ; do
                key=${arg%%=*};
                value=${arg##*=};
                if [ "${key}" = "primary" ]; then
                    echo $value > /sys/class/net/${bondname}/bonding/$key
                fi
            done

            > /tmp/bond.$bondname.up

            NO_BOND_MASTER=yes ifup $bondname
            exit $?
        done
    done
fi

if [ -z "$NO_TEAM_MASTER" ]; then
    for i in /tmp/team.*.info; do
        [ -e "$i" ] || continue
        unset teammaster
        unset teamslaves
        . "$i"
        for slave in $teamslaves ; do
            [ "$netif" != "$slave" ] && continue

            [ -e /tmp/team.$teammaster.up ] && exit 0

            # wait for all slaves to show up
            for slave in $teamslaves ; do
                # try to create the slave (maybe vlan or bridge)
                NO_BOND_MASTER=yes NO_AUTO_DHCP=yes ifup $slave

                if ! ip link show dev $slave >/dev/null 2>&1; then
                    # wait for the last slave to show up
                    exit 0
                fi
            done

            if [ ! -e /tmp/team.$teammaster.up ] ; then
                # We shall only bring up those _can_ come up
                # in case of some slave is gone in active-backup mode
                working_slaves=""
                for slave in $teamslaves ; do
                    ip link set $slave up 2>/dev/null
                    if wait_for_if_up $slave; then
                        working_slaves="$working_slaves$slave "
                    fi
                done
                # Do not add slaves now
                teamd -d -U -n -N -t $teammaster -f /etc/teamd/$teammaster.conf
                for slave in $working_slaves; do
                    # team requires the slaves to be down before joining team
                    ip link set $slave down
                    teamdctl $teammaster port add $slave
                done

                ip link set $teammaster up

                > /tmp/team.$teammaster.up
                NO_TEAM_MASTER=yes ifup $teammaster
                exit $?
            fi
        done
    done
fi

# all synthetic interfaces done.. now check if the interface is available
if ! ip link show dev $netif >/dev/null 2>&1; then
    exit 1
fi

# disable manual ifup while netroot is set for simplifying our logic
# in netroot case we prefer netroot to bringup $netif automaticlly
[ -n "$2" -a "$2" = "-m" ] && [ -z "$netroot" ] && manualup="$2"

if [ -e /tmp/bridge.info ]; then
    . /tmp/bridge.info
# start bridge if necessary
if [ -n "$manualup" ]; then
    >/tmp/net.$netif.manualup
    rm -f /tmp/net.${netif}.did-setup
else
    [ -e /tmp/net.${netif}.did-setup ] && exit 0
    [ -e /sys/class/net/$netif/address ] && \
        [ -e /tmp/net.$(cat /sys/class/net/$netif/address).did-setup ] && exit 0
fi


# No ip lines default to dhcp
ip=$(getarg ip)

if [ -z "$NO_AUTO_DHCP" ] && [ -z "$ip" ]; then
    if [ "$netroot" = "dhcp6" ]; then
        do_dhcp -6
    else
        do_dhcp -4
    fi

    for s in $(getargs nameserver); do
        [ -n "$s" ] || continue
        echo nameserver $s >> /tmp/net.$netif.resolv.conf
    done
fi


# Specific configuration, spin through the kernel command line
# looking for ip= lines
for p in $(getargs ip=); do
    ip_to_var $p
    # skip ibft
    [ "$autoconf" = "ibft" ] && continue

    # skip if same configuration appears twice
    while read line
    do
      [ "$line" = "$p" ] && continue 2
    done < /tmp/net.${netif}.conf

    echo $p >> /tmp/net.${netif}.conf

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
    [ -n "$dev" ] && [ "$dev" != "$netif" ] && continue

    for autoopt in $(str_replace "$autoconf" "," " "); do
        case $autoopt in
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
    done
    ret=$?

    # setup nameserver
    for s in "$dns1" "$dns2" $(getargs nameserver); do
        [ -n "$s" ] || continue
        echo nameserver $s >> /tmp/net.$netif.resolv.conf
    done

    for autoopt in $(str_replace "$autoconf" "," " "); do
        case $autoopt in
            dhcp4|dhcp|on|any)

    if [ $ret -eq 0 ]; then
        > /tmp/net.${netif}.up

        if [ -e /sys/class/net/${netif}/address ]; then
            > /tmp/net.$(cat /sys/class/net/${netif}/address).up
        fi

        setup_net $netif
        source_hook initqueue/online $netif
        if [ -z "$manualup" ]; then
            /sbin/netroot $netif
        fi
    fi
done

# no ip option directed at our interface?
if [ -z "$NO_AUTO_DHCP" ] && [ ! -e /tmp/net.${netif}.up ]; then
    if [ -e /tmp/net.bootdev ]; then
        BOOTDEV=$(cat /tmp/net.bootdev)
        if [ "$netif" = "$BOOTDEV" ] || [ "$BOOTDEV" = "$(cat /sys/class/net/${netif}/address)" ]; then
            load_ipv6
            do_dhcp
        fi
    else
        if getargs 'ip=dhcp6'; then
            load_ipv6
            do_dhcp -6
        fi
        if getargs 'ip=dhcp'; then
            do_dhcp -4
        fi
    fi
fi

if [ -e /tmp/net.${netif}.up ]; then
    > /tmp/net.$netif.did-setup
    [ -e /sys/class/net/$netif/address ] && \
        > /tmp/net.$(cat /sys/class/net/$netif/address).did-setup
fi
exit 0
