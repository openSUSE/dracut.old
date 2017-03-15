#!/bin/bash

# called by dracut
check() {
    return 255
}

# called by dracut
depends() {
    return 0
}

# called by dracut
installkernel() {
    local _fipsmodules _mod
    _fipsmodules="ansi_cprng arc4 authenc ccm "
    _fipsmodules+="ctr cts deflate drbg "
    _fipsmodules+="ecb fcrypt gcm ghash_generic khazad md4 michael_mic rmd128 "
    _fipsmodules+="rmd160 rmd256 rmd320 seed "
    _fipsmodules+="sha512_generic tcrypt tea wp512 xts zlib "
    _fipsmodules+="aes_s390 des_s390 sha256_s390 ghash_s390 sha1_s390 sha512_s390 "
    _fipsmodules+="gf128mul "
    _fipsmodules+="cmac vmac xcbc salsa20_generic salsa20_x86_64 camellia_generic camellia_x86_64 pcbc tgr192 anubis "
    _fipsmodules+="cast6_generic cast5_generic cast_common sha512_ssse3 serpent_sse2_x86_64 serpent_generic twofish_generic "
    _fipsmodules+="ablk_helper cryptd twofish_x86_64_3way lrw glue_helper twofish_x86_64 twofish_common blowfish_generic "
    _fipsmodules+="blowfish_x86_64 blowfish_common des_generic cbc "

    mkdir -m 0755 -p "${initdir}/etc/modprobe.d"

    for _mod in $_fipsmodules; do
        if hostonly='' instmods -c -s $_mod; then
            echo $_mod >> "${initdir}/etc/fipsmodules"
            echo "blacklist $_mod" >> "${initdir}/etc/modprobe.d/fips.conf"
        fi
    done
}

# called by dracut
install() {
    local _dir
    inst_hook pre-trigger 01 "$moddir/fips-boot.sh"
    inst_hook pre-pivot 01 "$moddir/fips-noboot.sh"
    inst_script "$moddir/fips.sh" /sbin/fips.sh

    inst_multiple rmmod insmod mount uname umount fipscheck

    inst_libdir_file \
        fipscheck .fipscheck.hmac \
         libfipscheck.so.1 \
        .libfipscheck.so.1.hmac .libfipscheck.so.1.1.0.hmac \
         libcrypto.so.1.0.0       libssl.so.1.0.0 \
        .libcrypto.so.1.0.0.hmac .libssl.so.1.0.0.hmac \
        .libcryptsetup.so.4.5.0.hmac .libcryptsetup.so.4.hmac \
        .libgcrypt.so.20.hmac \
        libfreeblpriv3.so libfreeblpriv3.chk

    # we do not use prelink at SUSE
    #inst_multiple -o prelink

    inst_simple /etc/system-fips
}

