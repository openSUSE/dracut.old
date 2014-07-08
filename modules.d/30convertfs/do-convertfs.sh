#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

# This converts all, /usr/bin -> /bin, ... and /var/run -> /run
# Do not enable by default!
if getargbool 0 rd.convertfs; then
    info "Converting both /var/run to /run tmpfs and /usr/bin -> /bin"
    if getargbool 0 rd.debug; then
        bash -x convertfs "$NEWROOT" 2>&1 | vinfo
    else
        convertfs "$NEWROOT" 2>&1 | vinfo
    fi
elif ! test -L "$NEWROOT"/var/run; then
    # This only converts /var/run -> /run as tmpfs
    info "Converting /var/run to /run tmpfs"
    if getargbool 0 rd.debug; then
        bash -x convertrunfs "$NEWROOT" 2>&1 | vinfo
    else
        convertrunfs "$NEWROOT" 2>&1 | vinfo
    fi
fi
