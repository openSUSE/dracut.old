#!/bin/sh

MD_UUID=$(getargs rd.md.uuid -d rd_MD_UUID=)
MD_RULES=/etc/udev/rules.d/62-md-dracut-uuid.rules

if ( ! [ -n "$MD_UUID" ] && ! getargbool 0 rd.auto ) || ! getargbool 1 rd.md -d -n rd_NO_MD; then
    info "rd.md=0: removing MD RAID activation"
    udevproperty rd_NO_MD=1
else
    # Create md rule to only process the specified raid array
    if [ -n "$MD_UUID" ]; then
        printf 'ACTION!="add|change", GOTO="md_uuid_end"\n' > $MD_RULES
        printf 'SUBSYSTEM!="block", GOTO="md_uuid_end"\n' >> $MD_RULES
        printf 'ENV{ID_FS_TYPE}!="ddf_raid_member", ENV{ID_FS_TYPE}!="isw_raid_member", ENV{ID_FS_TYPE}!="linux_raid_member", GOTO="md_uuid_end"\n' >> $MD_RULES

        #check for array components
        printf 'IMPORT{program}="/sbin/mdadm --examine --export $tempnode"\n' >> $MD_RULES
        for uuid in $MD_UUID; do
            printf 'ENV{MD_UUID}=="%s", GOTO="md_uuid_ok"\n' $uuid >> $MD_RULES
            printf 'ENV{ID_FS_UUID}=="%s", GOTO="md_uuid_ok"\n' $uuid >> $MD_RULES
        done;
        printf 'ENV{ID_FS_TYPE}="unknown"\n' >> $MD_RULES
        printf 'GOTO="md_uuid_end"\n' >> $MD_RULES
        printf 'LABEL="md_uuid_ok"\n' >> $MD_RULES
        printf 'ENV{IMSM_NO_PLATFORM}="1"\n' >> $MD_RULES
        printf 'LABEL="md_uuid_end"\n' >> $MD_RULES
    fi
fi


if [ -e /etc/mdadm.conf ] && getargbool 1 rd.md.conf -d -n rd_NO_MDADMCONF; then
    udevproperty rd_MDADMCONF=1
    rm -f -- $hookdir/pre-pivot/*mdraid-cleanup.sh
fi

if ! getargbool 1 rd.md.conf -d -n rd_NO_MDADMCONF; then
    rm -f -- /etc/mdadm/mdadm.conf /etc/mdadm.conf
    ln -s $(command -v mdraid-cleanup) $hookdir/pre-pivot/31-mdraid-cleanup.sh 2>/dev/null
fi

# noiswmd nodmraid for anaconda / rc.sysinit compatibility
# note nodmraid really means nobiosraid, so we don't want MDIMSM then either
if ! getargbool 1 rd.md.imsm -d -n rd_NO_MDIMSM -n noiswmd -n nodmraid; then
    info "no MD RAID for imsm/isw raids"
    udevproperty rd_NO_MDIMSM=1
fi

# same thing with ddf containers
if ! getargbool 1 rd.md.ddf -n rd_NO_MDDDF -n noddfmd -n nodmraid; then
    info "no MD RAID for SNIA ddf raids"
    udevproperty rd_NO_MDDDF=1
fi

strstr "$(mdadm --help-options 2>&1)" offroot && udevproperty rd_MD_OFFROOT=--offroot
