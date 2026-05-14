#!/bin/bash
# 99esos dracut module - 带调试输出，确保 rt24_os0_rcpu.elf/rt24_os1_rcpu.elf 被安装到 ramdisk 的 /lib/firmware

check() {
    return 0
}

depends() {
    echo ""
    return 0
}

install() {
    echo "99esos: install() called, moddir=${moddir}" >&2

    local esos_files=("rt24_os0_rcpu.elf" "rt24_os1_rcpu.elf")
    local found_any=0

    for f in "${esos_files[@]}"; do
        if [ -f "${moddir}/${f}" ]; then
            echo "99esos: found ${moddir}/${f}, installing to /lib/firmware/${f}" >&2
            inst_simple "${moddir}/${f}" "/lib/firmware/${f}"
            found_any=1
        elif [ -f "/usr/lib/esos/${f}" ]; then
            echo "99esos: found /usr/lib/esos/${f} on host, installing to /lib/firmware/${f}" >&2
            inst_simple "/usr/lib/esos/${f}" "/lib/firmware/${f}"
            found_any=1
        else
            echo "99esos: WARNING: ${f} not found in module dir or /usr/lib/esos" >&2
        fi
    done

    if [ "${found_any}" -eq 0 ]; then
        echo "99esos: WARNING: no ESOS ELF files installed" >&2
    fi

    return 0
}