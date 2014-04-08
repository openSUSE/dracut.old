#!/bin/bash

# called by dracut
check() {
    return 255
}

# called by dracut
depends() {
    echo "network"
    return 0
}

# called by dracut
install() {
    inst_hook pre-pivot 85 "$moddir/write-ifcfg.sh"
}

