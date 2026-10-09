## UniFi Protect Viewer kiosk

Turns a Debian 12 or 13 machine (amd64 or arm64) into a dedicated
[unifi-protect-viewer](https://github.com/digital195/unifi-protect-viewer) screen.
It boots straight into the liveview in fullscreen with no desktop environment.

What `install.sh` does:

- Installs a minimal X server, a kiosk window manager and the Electron runtime libraries
- Downloads the latest Linux release for the machine's architecture into `/opt/unifi-protect-viewer`
- Creates a locked `upv` user that autologins on tty1 and runs the viewer in a restart loop
- Turns off screen blanking and DPMS
- Writes the viewer profile so the setup screen is skipped, if you pass credentials

### Existing headless Debian box

```sh
curl -fsSL https://raw.githubusercontent.com/cptechie/netboot.xyz-custom/master/unifi-protect-viewer/install.sh -o install.sh
sudo UPV_URL='https://192.168.1.1/protect/dashboard/<id>' \
     UPV_USERNAME='viewer' \
     UPV_PASSWORD='secret' \
     bash install.sh
```

The viewer starts on the attached display as soon as the script finishes.
Re-run the same command to upgrade or to change the Protect login.

| Variable | Purpose |
| --- | --- |
| `UPV_URL` `UPV_USERNAME` `UPV_PASSWORD` | Protect login. Omit to use the on-screen setup instead. |
| `UPV_VERSION` | Pin a release tag such as `v1.1.5`. Default is the latest release. |
| `UPV_MONITOR` | 1-based display index for multi-monitor machines. |
| `UPV_ROTATE` | `left`, `right` or `inverted` for portrait or flipped screens. |
| `UPV_USER` | Kiosk account name. Default is `upv`. |
| `UPV_WIFI` | `1` installs Wi-Fi tools (NetworkManager). Join a network with `sudo nmtui`. |

Use a local Protect user with view-only permissions. The app stores the password
in plain text in `~upv/.config/unifi-protect-viewer/config.json`.

### Bare metal over netboot.xyz

Pick **Custom > Debian 13 kiosk** in netboot.xyz. Toggle options with Enter, then pick **Install**:

| Option | Off (default) | On |
| --- | --- | --- |
| Choose disk | Installs to the first disk found | Shows the installer's disk list (`preseed-ask.cfg`) |
| Confirm erase | Erases the disk without asking | Asks "Write the changes to disks?" (`upv_confirm=1`) |
| Wi-Fi | Wired networking only | Installs NetworkManager (`upv_wifi=1`) |

With every option off, the boot line is the same as before. Each option that is on
adds one short flag to it. Both preseeds share `common.cfg` and load Debian's non-free
firmware bundle so network cards that need firmware (such as Realtek) work. The
installer stops to ask for a password for the `localadmin` sudo account. The
selected disk is **erased**.

When it reboots, the viewer opens its setup screen. Enter the Protect URL, username
and password there with a keyboard, or SSH in as `localadmin` and re-run `install.sh`
with the `UPV_*` variables.

### Troubleshooting

- X and viewer output: `~upv/.xsession.log`
- Viewer log: `~upv/.config/unifi-protect-viewer/upv.log`
- Restart the kiosk session: `sudo systemctl restart getty@tty1`
