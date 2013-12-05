#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

# called by dracut
check() {
    [ -e /etc/localtime -a -e /etc/adjtime ]
}

# called by dracut
depends() {
    return 0
}

# called by dracut
install() {
    inst /usr/share/zoneinfo/UTC
    inst /etc/localtime
    inst /etc/adjtime
    inst_hook pre-trigger 00 "$moddir/warpclock.sh"
    inst /sbin/hwclock
}
