#!/bin/bash

# called by dracut
check() {
    [[ "$mount_needs" ]] && return 1
    # Don't include plymouth if plymouth-dracut package not installed
    [ -x /usr/lib/plymouth/plymouth-populate-initrd ] || return 1
    require_binaries plymouthd plymouth plymouth-set-default-theme
}

# called by dracut
depends() {
    echo drm
}

# called by dracut
install() {
    PKGLIBDIR="/usr/lib/plymouth"
    # breaks if dpkg is installed on openSUSE
    #if type -P dpkg-architecture &>/dev/null; then
    #    PKGLIBDIR="/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)/plymouth"
    #fi
    [ -x /usr/libexec/plymouth/plymouth-populate-initrd ] && PKGLIBDIR="/usr/libexec/plymouth"

    if grep -q nash ${PKGLIBDIR}/plymouth-populate-initrd \
        || [ ! -x ${PKGLIBDIR}/plymouth-populate-initrd ]; then
        . "$moddir"/plymouth-populate-initrd.sh
    else
        PLYMOUTH_POPULATE_SOURCE_FUNCTIONS="$dracutfunctions" \
            ${PKGLIBDIR}/plymouth-populate-initrd -t "$initdir"
    fi

    inst_hook emergency 50 "$moddir"/plymouth-emergency.sh

    inst_multiple readlink

    if ! dracut_module_included "systemd"; then
        inst_hook pre-trigger 10 "$moddir"/plymouth-pretrigger.sh
        inst_hook pre-pivot 90 "$moddir"/plymouth-newroot.sh
    fi
}

