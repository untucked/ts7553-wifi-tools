#!/usr/bin/env bash
set -euo pipefail

IFACE="${IFACE:-wlan0}"
CTRL="${CTRL:-/run/wpa_supplicant}"

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

log() {
    printf '%s\n' "$*"
}

stop_wpa() {
    if have_cmd wpa_cli && wpa_cli -p "$CTRL" -i "$IFACE" ping >/dev/null 2>&1; then
        wpa_cli -p "$CTRL" -i "$IFACE" terminate >/dev/null 2>&1 || true
        sleep 1
    fi

    if have_cmd pkill; then
        pkill -f "wpa_supplicant .*-[i] ?$IFACE( |$)" >/dev/null 2>&1 || true
        pkill -f "wpa_supplicant .* -i ?$IFACE( |$)" >/dev/null 2>&1 || true
    fi
}

main() {
    log "Disabling Wi-Fi on $IFACE"

    if have_cmd dhclient; then
        dhclient -r "$IFACE" || true
    fi

    stop_wpa

    if have_cmd ip; then
        ip link set "$IFACE" down || true
        ip link show "$IFACE"
    else
        log "ip command not found; could not bring $IFACE down or show final link state"
    fi
}

main "$@"
