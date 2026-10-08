#!/usr/bin/env bash
#
# Installs digital195/unifi-protect-viewer on a headless Debian 12/13 box and
# turns it into a kiosk: autologin on tty1 -> X -> viewer in fullscreen.
#
# Usage (as root):
#   curl -fsSL https://raw.githubusercontent.com/cptechie/netboot.xyz-custom/master/unifi-protect-viewer/install.sh | bash
#
# Optional environment variables:
#   UPV_URL        Protect liveview URL, e.g. https://192.168.1.1/protect/dashboard/<id>
#   UPV_USERNAME   Protect username (a local, view-only account is recommended)
#   UPV_PASSWORD   Protect password
#   UPV_VERSION    Release tag to install (default: latest), e.g. v1.1.5
#   UPV_USER       Local kiosk account (default: upv)
#   UPV_MONITOR    1-based display index passed to --monitor (default: unset)
#   UPV_ROTATE     xrandr rotation: normal|left|right|inverted (default: unset)
#   UPV_WIFI       1 to install Wi-Fi tools (NetworkManager, wpasupplicant, iw)
#
# If UPV_URL/UPV_USERNAME/UPV_PASSWORD are set, the viewer config is written so
# the first-launch setup screen is skipped. Re-run with new values to change it.
# The script is idempotent: re-running it upgrades to the newest release.

set -euo pipefail

REPO="digital195/unifi-protect-viewer"
INSTALL_DIR="/opt/unifi-protect-viewer"
KIOSK_USER="${UPV_USER:-upv}"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root (sudo -E bash install.sh)."
[ -r /etc/debian_version ] || die "This script targets Debian."

# Inside the debian-installer late_command chroot systemd is not running.
systemd_running() { [ -d /run/systemd/system ]; }

# ── Architecture ──────────────────────────────────────────────────────────────
case "$(dpkg --print-architecture)" in
  amd64) ARCH=x64 ;;
  arm64) ARCH=arm64 ;;
  *) die "Unsupported architecture: $(dpkg --print-architecture). Releases exist for amd64 and arm64." ;;
esac

# ── Packages ──────────────────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
log "Updating package lists"
apt-get update -qq

# Prints the first package name in the list that apt can install. Debian 13
# renamed several libraries with a t64 suffix, so try that variant first.
pick() {
  local p
  for p in "$@"; do
    if apt-cache show "$p" >/dev/null 2>&1; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

PKGS=(
  ca-certificates curl unzip uuid-runtime
  xserver-xorg xinit x11-xserver-utils x11-xkb-utils
  libnss3 libgbm1 libxss1 libxtst6 libsecret-1-0 libdrm2 libxkbcommon0 libnotify4
  fonts-dejavu-core
)
for lib in libgtk-3-0 libasound2 libatk-bridge2.0-0 libatspi2.0-0 libcups2; do
  PKGS+=("$(pick "${lib}t64" "$lib")") || die "No installable package for $lib"
done
WM="$(pick matchbox-window-manager openbox)" || die "No window manager package found"
PKGS+=("$WM")
CURSOR_HIDER="$(pick unclutter-xfixes unclutter || true)"
if [ -n "$CURSOR_HIDER" ]; then PKGS+=("$CURSOR_HIDER"); fi
# NetworkManager leaves interfaces listed in /etc/network/interfaces (the
# wired port set up by the installer) alone and manages Wi-Fi. Join a
# network with: sudo nmtui
if [ "${UPV_WIFI:-}" = "1" ]; then PKGS+=(network-manager wpasupplicant iw); fi

log "Installing ${#PKGS[@]} packages"
apt-get install -y -qq --no-install-recommends "${PKGS[@]}"

# ── Download release ──────────────────────────────────────────────────────────
resolve_latest() {
  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
  if [ -z "$tag" ]; then
    # API rate limited: fall back to the /releases/latest redirect.
    tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" \
      | sed -n 's#.*/tag/##p')"
  fi
  printf '%s\n' "$tag"
}

TAG="${UPV_VERSION:-$(resolve_latest)}"
[ -n "$TAG" ] || die "Could not determine the latest release. Set UPV_VERSION=vX.Y.Z."
VERSION="${TAG#v}"
ASSET="unifi-protect-viewer-linux-${ARCH}-${VERSION}.zip"

if [ -f "$INSTALL_DIR/.release" ] && [ "$(cat "$INSTALL_DIR/.release")" = "$ASSET" ]; then
  log "$ASSET already installed"
else
  log "Downloading $ASSET"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fL --retry 3 --progress-bar -o "$TMP/upv.zip" "https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"
  unzip -q "$TMP/upv.zip" -d "$TMP/x"
  # The archive holds a single top-level folder whose name does not always
  # match the tag, so locate it by the binary instead of guessing.
  SRC="$(dirname "$(find "$TMP/x" -maxdepth 2 -type f -name unifi-protect-viewer | head -n1)")"
  [ -x "$SRC/unifi-protect-viewer" ] || die "Binary not found in $ASSET"
  rm -rf "$INSTALL_DIR"
  mv "$SRC" "$INSTALL_DIR"
  chown -R root:root "$INSTALL_DIR"
  chmod -R u=rwX,go=rX "$INSTALL_DIR"
  # Electron's setuid sandbox helper must be root-owned and setuid.
  chown root:root "$INSTALL_DIR/chrome-sandbox"
  chmod 4755 "$INSTALL_DIR/chrome-sandbox"
  echo "$ASSET" > "$INSTALL_DIR/.release"
fi
ln -sf "$INSTALL_DIR/unifi-protect-viewer" /usr/local/bin/unifi-protect-viewer

# ── Kiosk user ────────────────────────────────────────────────────────────────
if ! id "$KIOSK_USER" >/dev/null 2>&1; then
  log "Creating user $KIOSK_USER"
  useradd -m -s /bin/bash "$KIOSK_USER"
  passwd -l "$KIOSK_USER" >/dev/null
fi
for grp in video audio input render; do
  if getent group "$grp" >/dev/null; then usermod -aG "$grp" "$KIOSK_USER"; fi
done
KIOSK_HOME="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"

# ── Viewer config (skips the setup screen) ────────────────────────────────────
if [ -n "${UPV_URL:-}" ] && [ -n "${UPV_USERNAME:-}" ] && [ -n "${UPV_PASSWORD:-}" ]; then
  log "Writing viewer config for $UPV_URL"
  CONF_DIR="$KIOSK_HOME/.config/unifi-protect-viewer"
  install -d -o "$KIOSK_USER" -g "$KIOSK_USER" -m 700 "$KIOSK_HOME/.config" "$CONF_DIR"
  json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
  ID="$(uuidgen)"
  umask 077
  cat > "$CONF_DIR/config.json" <<EOF
{
  "profiles": [
    {
      "id": "$ID",
      "name": "Default",
      "url": "$(json_escape "$UPV_URL")",
      "username": "$(json_escape "$UPV_USERNAME")",
      "password": "$(json_escape "$UPV_PASSWORD")"
    }
  ],
  "activeProfileId": "$ID",
  "startupProfileId": "$ID",
  "startupSettings": { "profileId": "$ID", "fullscreen": true, "displayIndex": 0 },
  "init": true
}
EOF
  umask 022
  chown "$KIOSK_USER:$KIOSK_USER" "$CONF_DIR/config.json"
  chmod 600 "$CONF_DIR/config.json"
else
  log "No UPV_URL/UPV_USERNAME/UPV_PASSWORD given. The setup screen will show on first launch (F10 reopens it later)."
fi

# ── X session ─────────────────────────────────────────────────────────────────
log "Writing X session for $KIOSK_USER"
VIEWER_ARGS="--fullscreen"
if [ -n "${UPV_MONITOR:-}" ]; then VIEWER_ARGS="$VIEWER_ARGS --monitor ${UPV_MONITOR}"; fi

if [ "$WM" = "matchbox-window-manager" ]; then
  WM_CMD="matchbox-window-manager -use_titlebar no"
else
  WM_CMD="openbox"
fi
case "$CURSOR_HIDER" in
  unclutter-xfixes) HIDE_CMD="unclutter --timeout 3 &" ;;
  unclutter) HIDE_CMD="unclutter -idle 3 -root &" ;;
  *) HIDE_CMD=":" ;;
esac
ROTATE_CMD=":"
if [ -n "${UPV_ROTATE:-}" ]; then ROTATE_CMD="xrandr -o ${UPV_ROTATE}"; fi

cat > "$KIOSK_HOME/.xinitrc" <<EOF
#!/bin/sh
# Generated by unifi-protect-viewer/install.sh
xset s off
xset s noblank
xset -dpms
$ROTATE_CMD
$HIDE_CMD
$WM_CMD &

# Relaunch the viewer if it exits or crashes.
while true; do
  /opt/unifi-protect-viewer/unifi-protect-viewer $VIEWER_ARGS
  sleep 3
done
EOF

cat > "$KIOSK_HOME/.bash_profile" <<'EOF'
# Generated by unifi-protect-viewer/install.sh
# Start X on tty1 only, so SSH logins and other consoles get a normal shell.
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx -- -nolisten tcp vt1 >"$HOME/.xsession.log" 2>&1
fi
EOF
chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.xinitrc" "$KIOSK_HOME/.bash_profile"
chmod 755 "$KIOSK_HOME/.xinitrc"

# ── Autologin on tty1 ─────────────────────────────────────────────────────────
log "Enabling autologin for $KIOSK_USER on tty1"
install -d /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF

# Boot to the console, not a display manager, and stop the console from blanking.
systemctl set-default multi-user.target >/dev/null
if [ -f /etc/default/grub ] && ! grep -q 'consoleblank=0' /etc/default/grub; then
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 consoleblank=0"/' /etc/default/grub
  command -v update-grub >/dev/null && update-grub >/dev/null 2>&1 || true
fi

if systemd_running; then
  systemctl daemon-reload
  log "Starting the viewer on tty1"
  systemctl restart getty@tty1.service
fi

log "Done. Installed $ASSET for user $KIOSK_USER."
