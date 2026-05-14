# Troubleshooting

These notes assume manual Wi-Fi control with `wifi-on.sh` and `wifi-off.sh`, no NetworkManager, and no boot-time Wi-Fi service.

On TS-7553 systems, Ethernet may appear as `end0` rather than `eth0`.

## `wlan0` Is Missing

List interfaces:

```sh
ip link
```

Check kernel and firmware messages:

```sh
dmesg | grep -iE "wlan|wifi|firmware|80211|rtl|brcm|ath|mt76"
```

If no wireless interface appears, the driver or firmware may not be loaded, the hardware may not be present, or the interface may have a different name.

## `wlan0` Has MAC `00:00:00:00:00:00`

Some devices expose the Wi-Fi interface with an invalid MAC address after boot. `wifi-on.sh` brings the interface down, assigns a locally administered MAC address, and then brings the interface back up before starting `wpa_supplicant`.

Default:

```sh
sudo wifi-on.sh
```

Use a unique MAC per device on the same LAN:

```sh
sudo MAC=02:11:22:33:44:56 wifi-on.sh
```

## Scan Works but Association Fails

Check status:

```sh
wpa_cli -p /run/wpa_supplicant -i wlan0 status
```

Common causes:

- Wrong SSID or password.
- Hidden network missing `scan_ssid=1`.
- Incorrect country code in the config.
- Access point requires a security mode not represented in the config.
- Duplicate local MAC address on the LAN.

Review recent logs:

```sh
journalctl -n 50 -u wpa_supplicant.service --no-pager
dmesg | tail -n 80
```

## `wpa_cli` Cannot Connect to the Control Interface

Check that `wpa_supplicant` was started with the expected control directory:

```sh
wpa_cli -p /run/wpa_supplicant -i wlan0 status
```

Confirm the directory exists:

```sh
ls -ld /run/wpa_supplicant
```

If a global `wpa_supplicant.service` is already managing the interface, stop it or disable it before using these manual scripts.

## DHCP Fails

Release and request a lease:

```sh
sudo dhclient -r wlan0
sudo dhclient -v wlan0
```

Check link state and routes:

```sh
ip addr show wlan0
ip route
```

If association succeeded but DHCP fails, check the access point DHCP server, MAC filters, VLANs, or whether another device is using the same local MAC address.

## DHCP Succeeds but `ping` Says Network Is Unreachable

On TS-7553 systems, a stale Ethernet default route can remain on `end0` even after Wi-Fi gets a DHCP lease on `wlan0`:

```text
default via 10.0.0.1 dev end0 linkdown
10.0.0.0/24 dev end0 proto kernel scope link src 10.0.0.193 linkdown
10.0.0.0/24 dev wlan0 proto kernel scope link src 10.0.0.75
```

When this happens, Linux may try the linkdown Ethernet route instead of Wi-Fi and report:

```text
ping: connect: Network is unreachable
```

`wifi-on.sh` now checks the gateway learned from DHCP on `wlan0`, removes stale `end0` default routes, removes `end0` routes when Ethernet is down or has no carrier, and replaces the default route through Wi-Fi:

```text
default via <gateway> dev wlan0
```

Check the current route table:

```sh
ip route
```

If your Ethernet interface has a different name, override it:

```sh
sudo ETH_IFACE=eth0 wifi-on.sh
```

## `ping 8.8.8.8` Works but `ping google.com` Fails

This usually means the Wi-Fi link and routing work, but DNS is not configured correctly.

Check resolver configuration:

```sh
cat /etc/resolv.conf
```

Then check whether your DHCP client is updating DNS or whether the system expects DNS settings from another network stack.

## Boot Is Slow Because Global Wi-Fi Is Enabled

Check enabled or installed network-related units:

```sh
systemctl list-unit-files | grep -iE "wifi|wpa|network|dhcp"
```

If you want Wi-Fi off by default and do not need the global `wpa_supplicant.service`, disable it:

```sh
sudo systemctl disable --now wpa_supplicant.service
```

The installer will not do this automatically unless you explicitly pass:

```sh
sudo ./scripts/install.sh --disable-global-wpa
```
