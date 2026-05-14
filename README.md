# ts7553-wifi-tools

Small Linux utilities for manually enabling and disabling Wi-Fi on TS-7553 and similar embedded Linux devices.

This repo is intentionally manual. Wi-Fi should stay off by default at boot, and an operator should turn it on only when needed, then turn it off when finished. The scripts do not install or enable any boot-time Wi-Fi service.

Some TS-7553/FMG devices expose `wlan0` but boot with a blank or invalid MAC address such as `00:00:00:00:00:00`. `wifi-on.sh` applies a locally administered MAC address before starting `wpa_supplicant` so the interface can associate normally. Every device on the same LAN needs a unique local MAC address to avoid conflicts.

On TS-7553 systems, Ethernet may appear as `end0`. After Wi-Fi DHCP succeeds, `wifi-on.sh` checks for stale `end0` routes, removes linkdown Ethernet routes when appropriate, and moves the default route to `wlan0`.

## Install

```sh
git clone https://github.com/untucked/ts7553-wifi-tools.git
cd ts7553-wifi-tools
sudo ./scripts/install.sh
```

This installs:

```text
/usr/local/sbin/wifi-on.sh
/usr/local/sbin/wifi-off.sh
```

The installer does not enable any systemd service or create any boot-time auto-start.

If you want Wi-Fi off by default and your system has a global `wpa_supplicant.service` enabled, you can disable it manually:

```sh
sudo systemctl disable --now wpa_supplicant.service
```

Or ask the installer to do only that explicit extra action:

```sh
sudo ./scripts/install.sh --disable-global-wpa
```

## Add Wi-Fi Credentials

Create `/etc/wpa_supplicant-wlan0.conf` from the example or append networks with `wpa_passphrase`:

```sh
sudo wpa_passphrase "SSID" 'PASSWORD' | sudo tee -a /etc/wpa_supplicant-wlan0.conf > /dev/null
```

Append, do not overwrite. Use `>>` or `tee -a`, not `>`, when adding a new network.

Remove plaintext password comments after generating the hashed PSK:

```sh
sudo sed -i '/^[[:space:]]*#psk=/d' /etc/wpa_supplicant-wlan0.conf
```

List configured SSIDs without showing passwords or PSKs:

```sh
sudo sed -n 's/^[[:space:]]*ssid="\([^"]*\)".*/\1/p' /etc/wpa_supplicant-wlan0.conf
```

Security notes:

- Do not commit `/etc/wpa_supplicant-wlan0.conf`.
- Do not commit SSIDs, passwords, serial numbers, private IP addresses, or environment-specific configuration.

## Manual Use

Turn Wi-Fi on:

```sh
sudo wifi-on.sh
```

Turn Wi-Fi off:

```sh
sudo wifi-off.sh
```

Override defaults with environment variables:

```sh
sudo MAC=02:11:22:33:44:56 wifi-on.sh
sudo IFACE=wlan1 wifi-on.sh
sudo IFACE=wlan1 MAC=02:11:22:33:44:56 wifi-on.sh
```

Defaults:

```sh
IFACE=wlan0
ETH_IFACE=end0
MAC=02:11:22:33:44:55
CONF=/etc/wpa_supplicant-wlan0.conf
CTRL=/run/wpa_supplicant
ASSOC_TIMEOUT_SEC=20
FALLBACK_GW=10.0.0.1
```

`FALLBACK_GW` is only used if `wifi-on.sh` cannot detect the Wi-Fi gateway from DHCP-created routes.

## Verify

```sh
wpa_cli -p /run/wpa_supplicant -i wlan0 status
ip addr show wlan0
ip route
ping -c 3 8.8.8.8
ping -c 3 google.com
```

If `ping 8.8.8.8` works but `ping google.com` fails, the Wi-Fi link is probably up and DNS needs attention.

After `wifi-on.sh` runs, the route table should include a default route through Wi-Fi:

```text
default via <gateway> dev wlan0
```

It should not prefer a stale linkdown Ethernet route such as:

```text
default via <gateway> dev end0 linkdown
```

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).
