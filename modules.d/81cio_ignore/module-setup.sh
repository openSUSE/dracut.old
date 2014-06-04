#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

# called by dracut
check() {
# do not add this module by default
	local arch=$(uname -m)
	[ "$arch" = "s390" -o "$arch" = "s390x" ] || return 1
	return 0
}

find_mount() {
	local dev mnt etc wanted_dev
	wanted_dev="$(readlink -e -q $1)"
	while read dev mnt etc; do
		[ "$mnt" = "$wanted_dev" ] && echo "$dev" && return 0
	done < /proc/mounts
	return 1
}

cmdline() {
	local zipl_dasd
	zipl_dasd=`find_mount /boot/zipl`
	printf " rd.zipl_dasd=%s\n" "$zipl_dasd "
}

# called by dracut
install() {
	if [[ $hostonly_cmdline == "yes" ]];then
		echo $(cmdline) >"${initdir}/etc/cmdline.d/01zipl_dasd.conf"
	fi

	inst_hook pre-mount 10 "$moddir/parse-zipl.sh"
	inst_multiple cio_ignore mount umount mkdir
}
installkernel() {
	instmods ext4
}
