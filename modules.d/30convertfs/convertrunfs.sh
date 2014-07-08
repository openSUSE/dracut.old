#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

ROOT="$1"

if [[ ! -d "$ROOT" ]]; then
    echo "Usage: $0 <rootdir>"
    exit 1
fi

if [[ "$ROOT" -ef / ]]; then
    echo "Can't convert the running system."
    echo "Please boot with 'rd.convertfs' on the kernel command line,"
    echo "to update with the help of the initramfs,"
    echo "or run this script from a rescue system."
    exit 1
fi

while [[ "$ROOT" != "${ROOT%/}" ]]; do
    ROOT=${ROOT%/}
done

if findmnt "$ROOT" -O ro;then
    WAS_RO=1
    mount $ROOT -o remount,rw
else
    WAS_RO=0
fi

testfile="$ROOT/.usrmovecheck$$"
rm -f -- "$testfile"
> "$testfile"
if [[ ! -e "$testfile" ]]; then
    echo "Cannot write to $ROOT/"
    exit 1
fi
rm -f -- "$testfile"

if [ ! -L $ROOT/var/run -a -e $ROOT/var/run -a -d $ROOT/run ]; then
    echo "Converting /var/run to symlink"
    mv -f $ROOT/var/run $ROOT/var/run.runmove~
    ln -sfn ../run $ROOT/var/run
fi

if [ ! -L $ROOT/var/lock -a -e $ROOT/var/lock -a -d $ROOT/run ]; then
    echo "Converting /var/lock to symlink"
    mv -f $ROOT/var/lock $ROOT/var/lock.lockmove~
    ln -sfn ../run/lock $ROOT/var/lock
fi

if [ $WAS_RO -eq 1 ];then
    mount $ROOT -o remount,ro
fi
