#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

ZIPL_DEV="$(getarg rd.zipl_dasd)"
ZIPL_DIR=/tmp/zipl
CIO_REMOVE_LIST=$ZIPL_DIR/active_devices.txt

if [ -n $ZIPL_DEV ];then
	info "Waiting for zipl device $ZIPL_DEV"
	wait_for_dev -n "$ZIPL_DEV"
#
#	mount device and read devices
#
	[ -d $ZIPL_DIR ] ||  mkdir $ZIPL_DIR
	mount -t ext2 -o ro $ZIPL_DEV $ZIPL_DIR
	if [ -f $CIO_REMOVE_LIST ] ; then
#
#	File exist
#
		while read dev etc; do
		    [ "$dev" = "#" -o "$dev" = "" ] && continue
		    cio_ignore --remove $dev
		done < $CIO_REMOVE_LIST
	fi
	umount $ZIPL_DIR
else
	warn "No rd.zipl_dasd boot parameter found"
fi
