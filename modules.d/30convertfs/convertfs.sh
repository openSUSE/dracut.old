#!/bin/bash

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

#mount /sysroot rw
[ -w $ROOT ] || mount -o remount,rw $ROOT

if [ ! -L $ROOT/var/run -a -e $ROOT/var/run ]; then
    echo "Converting /var/run to symlink"
    mv -f $ROOT/var/run $ROOT/var/run.runmove~
    ln -sfn ../run $ROOT/var/run
fi

if [ ! -L $ROOT/var/lock -a -e $ROOT/var/lock ]; then
    echo "Converting /var/lock to symlink"
    mv -f $ROOT/var/lock $ROOT/var/lock.lockmove~
    ln -sfn ../run/lock $ROOT/var/lock
fi

[ -w $ROOT ] && mount -o remount,ro $ROOT

echo "Done."
exit 0
