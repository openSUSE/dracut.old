#!/bin/bash

# called by dracut
installkernel() {
    if [[ -z $drivers ]]; then
        block_module_filter() {
            local _blockfuncs='ahci_platform_get_resources|ata_scsi_ioctl|scsi_add_host|blk_cleanup_queue|register_mtd_blktrans|scsi_esp_register|register_virtio_device|usb_stor_disconnect|mmc_add_host|sdhci_add_host'
            # subfunctions inherit following FDs
            local _merge=8 _side2=9
            function bmf1() {
                local _f
                while read _f || [ -n "$_f" ]; do case "$_f" in
                    *.ko)    [[ $(cat       "$_f" | tr -cd '[:print:]') =~ $_blockfuncs ]] && echo "$_f" ;;
                    *.ko.gz) [[ $(gzip -dc <"$_f" | tr -cd '[:print:]') =~ $_blockfuncs ]] && echo "$_f" ;;
                    *.ko.xz) [[ $(xz -dc   <"$_f" | tr -cd '[:print:]') =~ $_blockfuncs ]] && echo "$_f" ;;
                    esac
                done
                return 0
            }
            function rotor() {
                local _f1 _f2
                while read _f1 || [ -n "$_f1" ]; do
                    echo "$_f1"
                    if read _f2; then
                        echo "$_f2" 1>&${_side2}
                    fi
                done | bmf1 1>&${_merge}
                return 0
            }
            # Use two parallel streams to filter alternating modules.
            set +x
            eval "( ( rotor ) ${_side2}>&1 | bmf1 ) ${_merge}>&1"
            [[ $debug ]] && set -x
            return 0
        }

        hostonly='' instmods \
            sr_mod sd_mod scsi_dh ata_piix hid_generic unix \
            ehci-hcd ehci-pci ehci-platform \
            ohci-hcd ohci-pci \
            uhci-hcd \
            pinctrl-cherryview pwm-lpss pwm-lpss-platform

        hostonly='' instmods \
            xhci-hcd xhci-pci xhci-plat-hcd \
            "=drivers/hid" \
            "=drivers/tty/serial" \
            "=drivers/input/serio" \
            "=drivers/input/keyboard" \
            "=drivers/usb/storage" \
            "=drivers/pci/host" \
            ${NULL}

        instmods \
            yenta_socket scsi_dh_rdac scsi_dh_emc scsi_dh_alua \
            atkbd i8042 usbhid firewire-ohci pcmcia hv-vmbus \
            virtio virtio_blk virtio_ring virtio_pci virtio_scsi \
            "=drivers/pcmcia" =ide nvme vmd

        if [[ "$(uname -m)" == arm* || "$(uname -m)" == aarch64 ]]; then
            # arm/aarch64 specific modules
            _blockfuncs+='|dw_mc_probe|dw_mci_pltfm_register'
            instmods \
                "=drivers/clk" \
                "=drivers/dma" \
                "=drivers/extcon" \
                "=drivers/hwspinlock" \
                "=drivers/i2c/busses" \
                "=drivers/mfd" \
                "=drivers/mmc/core" \
                "=drivers/phy" \
                "=drivers/power" \
                "=drivers/regulator" \
                "=drivers/rpmsg" \
                "=drivers/rtc" \
                "=drivers/soc" \
                "=drivers/usb/chipidea" \
                "=drivers/usb/dwc2" \
                "=drivers/usb/dwc3" \
                "=drivers/usb/host" \
                "=drivers/usb/misc" \
                "=drivers/usb/musb" \
                "=drivers/usb/phy" \
		"=drivers/scsi/hisi_sas" \
                ${NULL}
        fi

        find_kernel_modules  |  block_module_filter  |  instmods

	# modules that will fail block_module_filter because their implementation
	# is spread over multiple modules (bsc#1034597)
	instmods hisi_sas_v1_hw hisi_sas_v2_hw # symbols in dep hisi_sas_main

        # if not on hostonly mode, install all known filesystems,
        # if the required list is not set via the filesystems variable
        if ! [[ $hostonly ]]; then
            if [[ -z $filesystems ]]; then
                silent_omit_drivers="kernel/fs/nfs|kernel/fs/nfsd|kernel/fs/lockd" \
                    instmods '=fs'
            fi
        else
            for i in "${host_fs_types[@]}"; do
                hostonly='' instmods $i
            done
        fi
    fi
    :
}

# called by dracut
install() {
    inst_multiple -o /lib/modprobe.d/*.conf
    [[ $hostonly ]] && inst_multiple -H -o /etc/modprobe.d/*.conf /etc/modprobe.conf
    if ! dracut_module_included "systemd"; then
        inst_hook cmdline 01 "$moddir/parse-kernel.sh"
    fi
    inst_simple "$moddir/insmodpost.sh" /sbin/insmodpost.sh
}
