#!/usr/bin/env bash
set -euo pipefail

IFACE="${IFACE:-wlan0}"
ETH_IFACE="${ETH_IFACE:-end0}"
MAC="${MAC:-02:11:22:33:44:55}"
CONF="${CONF:-/etc/wpa_supplicant-wlan0.conf}"
CTRL="${CTRL:-/run/wpa_supplicant}"
ASSOC_TIMEOUT_SEC="${ASSOC_TIMEOUT_SEC:-20}"
FALLBACK_GW="${FALLBACK_GW:-10.0.0.1}"

log() {
    printf '%s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

require_cmd() {
    have_cmd "$1" || die "required command not found: $1"
}

print_diagnostics() {
    log "Diagnostics for $IFACE:"

    if have_cmd wpa_cli; then
        log ""
        log "wpa_cli status:"
        wpa_cli -p "$CTRL" -i "$IFACE" status || true
    fi

    if have_cmd ip; then
        log ""
        log "ip link show $IFACE:"
        ip link show "$IFACE" || true
    fi

    if have_cmd journalctl; then
        log ""
        log "recent wpa_supplicant journal entries:"
        journalctl -n 50 -u wpa_supplicant.service --no-pager || true
    elif have_cmd dmesg; then
        log ""
        log "recent kernel messages:"
        dmesg | tail -n 80 || true
    fi
}

stop_existing_wpa() {
    if have_cmd wpa_cli && wpa_cli -p "$CTRL" -i "$IFACE" ping >/dev/null 2>&1; then
        wpa_cli -p "$CTRL" -i "$IFACE" terminate >/dev/null 2>&1 || true
        sleep 1
    fi

    if have_cmd pkill; then
        pkill -f "wpa_supplicant .*-[i] ?$IFACE( |$)" >/dev/null 2>&1 || true
        pkill -f "wpa_supplicant .* -i ?$IFACE( |$)" >/dev/null 2>&1 || true
    fi
}

wait_for_association() {
    local elapsed=0
    local state=""

    while [ "$elapsed" -lt "$ASSOC_TIMEOUT_SEC" ]; do
        state="$(wpa_cli -p "$CTRL" -i "$IFACE" status 2>/dev/null | awk -F= '$1 == "wpa_state" { print $2 }' || true)"
        if [ "$state" = "COMPLETED" ]; then
            return 0
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    return 1
}

wifi_gateway() {
    local gateway=""

    gateway="$(ip route show default dev "$IFACE" 2>/dev/null | awk '/default/ { print $3; exit }')"
    if [ -z "$gateway" ]; then
        gateway="$(ip route show 2>/dev/null | awk -v iface="$IFACE" '$1 == "default" && $0 ~ ("dev " iface "($| )") { print $3; exit }')"
    fi

    printf '%s\n' "$gateway"
}

delete_routes_for_dev() {
    local dev="$1"

    ip route show dev "$dev" 2>/dev/null | while IFS= read -r route; do
        [ -n "$route" ] || continue
        ip route del $route 2>/dev/null || true
    done
}

fix_wifi_routes() {
    local wifi_gw=""

    wifi_gw="$(wifi_gateway)"

    log ""
    log "Checking route priority for $IFACE"

    if ip link show "$ETH_IFACE" >/dev/null 2>&1; then
        log "Removing stale default routes for $ETH_IFACE, if present"
        ip route show default dev "$ETH_IFACE" 2>/dev/null | while IFS= read -r route; do
            [ -n "$route" ] || continue
            ip route del $route 2>/dev/null || true
        done

        if ip link show "$ETH_IFACE" 2>/dev/null | grep -qE 'NO-CARRIER|DOWN'; then
            log "$ETH_IFACE appears down or has no carrier; removing its stale routes"
            delete_routes_for_dev "$ETH_IFACE"
        fi
    fi

    if [ -z "$wifi_gw" ]; then
        log "WARNING: Could not detect $IFACE gateway from DHCP routes; using fallback gateway $FALLBACK_GW"
        wifi_gw="$FALLBACK_GW"
    fi

    if [ -n "$wifi_gw" ]; then
        log "Setting default route via $wifi_gw dev $IFACE"
        ip route replace default via "$wifi_gw" dev "$IFACE"
    else
        log "WARNING: Could not determine a Wi-Fi gateway; leaving default route unchanged"
    fi
}

main() {
    require_cmd ip
    require_cmd wpa_supplicant
    require_cmd wpa_cli
    require_cmd dhclient

    [ -f "$CONF" ] || die "wpa_supplicant config not found: $CONF"

    log "Enabling Wi-Fi on $IFACE with MAC $MAC"

    ip link set "$IFACE" down
    ip link set dev "$IFACE" address "$MAC"
    ip link set "$IFACE" up

    install -d -m 755 "$CTRL"

    stop_existing_wpa

    log "Starting wpa_supplicant"
    wpa_supplicant -B -i "$IFACE" -c "$CONF" -C "$CTRL"

    log "Waiting up to $ASSOC_TIMEOUT_SEC seconds for association"
    if ! wait_for_association; then
        print_diagnostics
        die "Wi-Fi association did not complete"
    fi

    log "Releasing any previous DHCP lease"
    dhclient -r "$IFACE" || true

    log "Requesting DHCP lease"
    dhclient -v "$IFACE"

    fix_wifi_routes

    log ""
    log "Interface address:"
    ip addr show "$IFACE"

    log ""
    log "Routes:"
    ip route
}

main "$@"
