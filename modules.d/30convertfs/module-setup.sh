#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

# called by dracut
check() {
    # Only check for /var/run
    if test -L /var/run;then
        return 255
    else
        require_binaries bash find ldconfig mv rm cp ln || return 1
        return 0
    fi
}

# called by dracut
depends() {
    return 0
}

# called by dracut
install() {
    inst_multiple bash find ldconfig mv rm cp ln
    inst_hook pre-pivot 99 "$moddir/do-convertfs.sh"
    inst_script "$moddir/convertfs.sh" /usr/bin/convertfs
    inst_script "$moddir/convertrunfs.sh" /usr/bin/convertrunfs
}

