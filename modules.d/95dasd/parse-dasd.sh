#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh
for dasd_arg in $(getargs rd.dasd= -d rd_DASD= DASD=); do
    (
        local OLDIFS="$IFS"
        local IFS=","
        set -- $dasd_arg
        IFS="$OLDIFS"
        echo "$@" | normalize_dasd_arg >> /etc/dasd.conf
    )
done
