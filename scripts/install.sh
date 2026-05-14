#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local/sbin}"
DISABLE_GLOBAL_WPA=0

usage() {
    cat <<USAGE
Usage: $0 [--disable-global-wpa]

Install wifi-on.sh and wifi-off.sh to $PREFIX.

Options:
  --disable-global-wpa   Also run: systemctl disable --now wpa_supplicant.service
  -h, --help             Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --disable-global-wpa)
            DISABLE_GLOBAL_WPA=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

install -d -m 755 "$PREFIX"
install -m 755 "$SCRIPT_DIR/wifi-on.sh" "$PREFIX/wifi-on.sh"
install -m 755 "$SCRIPT_DIR/wifi-off.sh" "$PREFIX/wifi-off.sh"

if [ "$DISABLE_GLOBAL_WPA" -eq 1 ]; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now wpa_supplicant.service
    else
        printf 'systemctl not found; could not disable wpa_supplicant.service\n' >&2
    fi
else
    cat <<NOTE

Note: no boot-time Wi-Fi service was enabled.
If you want Wi-Fi off by default and a global wpa_supplicant service is enabled, you can run:
  systemctl disable --now wpa_supplicant.service

Or rerun this installer with:
  $0 --disable-global-wpa
NOTE
fi

cat <<DONE

Installed:
  $PREFIX/wifi-on.sh
  $PREFIX/wifi-off.sh

Manual usage:
  wifi-on.sh
  wifi-off.sh
DONE
