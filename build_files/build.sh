#!/bin/bash
set -ouex pipefail

# Copy system_files/ from the repo into /
cp -avf /ctx/system_files/. /

### ----------------------------------------------------------------------------
### /opt is a symlink to /var/opt on ostree. Use a real /opt for the RPM
### installs, then move the files into the image and restore the link.
### ----------------------------------------------------------------------------

if [ -L /opt ]; then
    rm -f /opt
    mkdir /opt
fi

### Retry for transient network and HTTP 429 errors
retry() {
    local n=0
    until "$@"; do
        n=$((n+1))
        if [ "$n" -ge 3 ]; then
            echo "ERROR: failed after $n attempts: $*" >&2
            return 1
        fi
        echo "Attempt $n failed, retrying in $((n*30))s..."
        sleep $((n*30))
    done
}

### ----------------------------------------------------------------------------
### Cisco Secure Client (RPMs from /ctx/rpms, copied in by the Containerfile)
### Posture RPM is downloaded from the GitHub release (too big for rpms/)
### Asset is found via the public release page (the API returns 403 on shared runners)
### vpn-cli is excluded: it conflicts with the core vpn package
### vpn must install first: iseposture's pre-install check requires it
### ----------------------------------------------------------------------------

POSTURE_REPO="https://github.com/nsaldanh6327/aurora-corp-poc"
POSTURE_TAG="posture-5.1.20.333"
POSTURE_PATH="$(curl -fsSL --retry 3 --retry-delay 30 "$POSTURE_REPO/releases/expanded_assets/$POSTURE_TAG" \
    | grep -o "href=\"/nsaldanh6327/aurora-corp-poc/releases/download/$POSTURE_TAG/[^\"]*\.rpm\"" \
    | sed -E 's/^href="//; s/"$//' \
    | head -1)"
[ -n "$POSTURE_PATH" ] || { echo "ERROR: no .rpm asset found in release $POSTURE_TAG" >&2; exit 1; }
POSTURE_URL="https://github.com$POSTURE_PATH"
echo "Posture RPM: $POSTURE_URL"

POSTURE_DIR=/tmp/posture
mkdir -p "$POSTURE_DIR"
retry curl -fL --retry 3 -o "$POSTURE_DIR/cisco-secure-client-posture.rpm" "$POSTURE_URL"

shopt -s nullglob
VPN_RPMS=()
OTHER_RPMS=()
for rpm in /ctx/rpms/*.rpm "$POSTURE_DIR"/*.rpm; do
    name="$(basename "$rpm")"
    case "$name" in
        cisco-secure-client-vpn-cli-*) echo "Skipping $name (conflicts with vpn)" ;;
        cisco-secure-client-vpn-[0-9]*) VPN_RPMS+=("$rpm") ;;
        cisco-secure-client-*) OTHER_RPMS+=("$rpm") ;;
    esac
done
shopt -u nullglob

if [ "${#VPN_RPMS[@]}" -ne 1 ]; then
    echo "ERROR: expected exactly one cisco-secure-client-vpn RPM, found ${#VPN_RPMS[@]}" >&2
    exit 1
fi

dnf5 install -y "${VPN_RPMS[@]}"
if [ "${#OTHER_RPMS[@]}" -gt 0 ]; then
    dnf5 install -y "${OTHER_RPMS[@]}"
fi
rm -rf "$POSTURE_DIR"

rpm -qa | grep -i cisco
systemctl enable vpnagentd.service

### ----------------------------------------------------------------------------
### Move everything under /opt into the image and restore /opt -> /var/opt
### ----------------------------------------------------------------------------

echo "Contents of /opt before move:"
ls -la /opt

mkdir -p /usr/lib/opt
shopt -s dotglob nullglob
for item in /opt/*; do
    mv "$item" /usr/lib/opt/
done
shopt -u dotglob nullglob

rmdir /opt
ln -s var/opt /opt

mkdir -p /usr/lib/tmpfiles.d
{
    echo "d /var/opt 0755 root root -"
    for item in /usr/lib/opt/*; do
        [ -e "$item" ] || continue
        echo "L /var/opt/$(basename "$item") - - - - /usr/lib/opt/$(basename "$item")"
    done
} > /usr/lib/tmpfiles.d/corp-browsers.conf

### ----------------------------------------------------------------------------
### Cisco Secure Client trusted CA certificates
### Must come after the /opt move section (creates /usr/lib/opt/.cisco)
### ----------------------------------------------------------------------------

DIGICERT_CS_CA_URL="https://cacerts.digicert.com/DigiCertTrustedG4CodeSigningRSA4096SHA3842021CA1.crt"
DIGICERT_ROOT_G4_URL="https://cacerts.digicert.com/DigiCertTrustedRootG4.crt"

CISCO_CA_DIR=/usr/lib/opt/.cisco/certificates/ca
mkdir -p "$CISCO_CA_DIR" /etc/pki/ca-trust/source/anchors

retry bash -c "curl -fsSL '$DIGICERT_CS_CA_URL' | openssl x509 -inform DER -out '$CISCO_CA_DIR/DigiCertTrustedG4CodeSigningRSA4096SHA3842021CA1.pem'"
retry bash -c "curl -fsSL '$DIGICERT_ROOT_G4_URL' | openssl x509 -inform DER -out '$CISCO_CA_DIR/DigiCertTrustedRootG4.pem'"

openssl rehash "$CISCO_CA_DIR"
cp "$CISCO_CA_DIR"/*.pem /etc/pki/ca-trust/source/anchors/
update-ca-trust extract

# /var/opt/.cisco -> /usr/lib/opt/.cisco (dotfiles aren't covered by the glob above)
printf 'L+ /var/opt/.cisco - - - - /usr/lib/opt/.cisco\n' > /usr/lib/tmpfiles.d/cisco-secureclient.conf

restorecon -RF /usr/lib/opt/.cisco /usr/lib/tmpfiles.d/cisco-secureclient.conf 2>/dev/null || true

### ----------------------------------------------------------------------------
### Chrome (Flatpak, installed on first boot via preinstall; no vendor RPMs)
### ----------------------------------------------------------------------------

mkdir -p /usr/share/flatpak/remotes.d /usr/share/flatpak/preinstall.d
cat > /usr/share/flatpak/remotes.d/flathub.flatpakrepo <<'EOF'
[Flatpak Repo]
Title=Flathub
Url=https://dl.flathub.org/repo/
Homepage=https://flathub.org/
EOF

cat > /usr/share/flatpak/preinstall.d/chrome.preinstall <<'EOF'
[Flatpak Preinstall com.google.Chrome]
Branch=stable
EOF

cat > /usr/share/flatpak/preinstall.d/onlyoffice.preinstall <<'EOF'
[Flatpak Preinstall org.onlyoffice.desktopeditors]
Branch=stable
EOF

### ----------------------------------------------------------------------------
### Chrome managed policies: M365 PWAs force-installed
### Host policy dir is exposed read-only to the Flatpak via an override
### ----------------------------------------------------------------------------

M365_POLICY=/tmp/m365_pwas.json
cat > "$M365_POLICY" <<'EOF'
{
  "WebAppInstallForceList": [
    {"url": "https://outlook.cloud.microsoft/mail/", "fallback_app_name": "Outlook", "default_launch_container": "window", "create_desktop_shortcut": false},
    {"url": "https://teams.microsoft.com/v2/", "fallback_app_name": "Teams", "default_launch_container": "window", "create_desktop_shortcut": false},
    {"url": "https://onedrive.live.com/", "fallback_app_name": "OneDrive", "default_launch_container": "window", "create_desktop_shortcut": false},
    {"url": "https://word.cloud.microsoft/", "fallback_app_name": "Word", "default_launch_container": "window", "create_desktop_shortcut": false},
    {"url": "https://excel.cloud.microsoft/", "fallback_app_name": "Excel", "default_launch_container": "window", "create_desktop_shortcut": false},
    {"url": "https://powerpoint.cloud.microsoft/", "fallback_app_name": "PowerPoint", "default_launch_container": "window", "create_desktop_shortcut": false}
  ]
}
EOF

python3 -m json.tool "$M365_POLICY" > /dev/null

mkdir -p /etc/opt/chrome/policies/managed
install -m 0644 "$M365_POLICY" /etc/opt/chrome/policies/managed/m365_pwas.json
rm -f "$M365_POLICY"

mkdir -p /etc/flatpak/overrides
cat > /etc/flatpak/overrides/com.google.Chrome <<'EOF'
[Context]
filesystems=/etc/opt/chrome:ro
EOF

# Remove any Edge leftovers from earlier builds
rm -rf /etc/opt/edge /etc/yum.repos.d/microsoft-edge.repo /etc/yum.repos.d/google-chrome.repo

### ----------------------------------------------------------------------------
### Office web app launchers (run through Chrome Flatpak, fixed IDs for pinning)
### Icons come from /usr/share/rexel-icons (already in system_files)
### ----------------------------------------------------------------------------

APPS=(
  "outlook|Outlook|https://outlook.cloud.microsoft/mail/"
  "teams|Teams|https://teams.microsoft.com/v2/"
  "onedrive|OneDrive|https://onedrive.live.com/"
  "word|Word|https://word.cloud.microsoft/"
  "excel|Excel|https://excel.cloud.microsoft/"
  "powerpoint|PowerPoint|https://powerpoint.cloud.microsoft/"
)

for entry in "${APPS[@]}"; do
    IFS='|' read -r id name url <<< "$entry"
    cat > "/usr/share/applications/rexel-${id}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${name}
Exec=flatpak run com.google.Chrome --app=${url} --no-first-run
Icon=/usr/share/rexel-icons/${id}.png
Categories=Office;
Terminal=false
EOF
done

### ----------------------------------------------------------------------------
### First-login taskbar pinning (per user, runs once)
### ----------------------------------------------------------------------------

cat > /usr/libexec/rexel-pin-taskbar.py <<'PYEOF'
#!/usr/bin/env python3
import configparser
import os
import re
import subprocess
import sys

CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
MARKER = os.path.join(CONFIG_HOME, "rexel-taskbar-pinned")
APPLETSRC = os.path.join(CONFIG_HOME, "plasma-org.kde.plasma.desktop-appletsrc")
PINS = [
    "applications:rexel-outlook.desktop",
    "applications:rexel-teams.desktop",
    "applications:rexel-onedrive.desktop",
    "applications:rexel-word.desktop",
    "applications:rexel-excel.desktop",
    "applications:rexel-powerpoint.desktop",
]

if os.path.exists(MARKER):
    sys.exit(0)

if not os.path.exists(APPLETSRC):
    # Plasma has not written its config yet; try again on the next login
    sys.exit(1)

cfg = configparser.ConfigParser(strict=False, interpolation=None)
cfg.optionxform = str
cfg.read(APPLETSRC)

applet_re = re.compile(r"^Containments\]\[\d+\]\[Applets\]\[\d+\]$")
changed = False

for section in list(cfg.sections()):
    if not applet_re.match(section):
        continue
    if cfg.get(section, "plugin", fallback="") != "org.kde.plasma.icontasks":
        continue

    conf = section + "][Configuration][General]"
    if not cfg.has_section(conf):
        cfg.add_section(conf)
    current = [x for x in cfg.get(conf, "launchers", fallback="").split(",") if x]
    for pin in PINS:
        if pin not in current:
            current.append(pin)
    cfg.set(conf, "launchers", ",".join(current))
    changed = True

if changed:
    with open(APPLETSRC, "w") as f:
        cfg.write(f, space_around_delimiters=False)
    # plasmashell rewrites its config on exit, so restart it to load the pins
    subprocess.run(["plasmashell", "--replace"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

os.makedirs(CONFIG_HOME, exist_ok=True)
open(MARKER, "w").close()
PYEOF
chmod 0755 /usr/libexec/rexel-pin-taskbar.py

mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/rexel-taskbar-pins.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Rexel taskbar pins
Exec=/usr/libexec/rexel-pin-taskbar.py
X-KDE-autostart-after=panel
NoDisplay=true
EOF

### ----------------------------------------------------------------------------
### Additional tools (Fedora repos)
### locate is provided by mlocate on Fedora
### ----------------------------------------------------------------------------

retry dnf5 install -y --setopt=retries=5 \
    remmina \
    filezilla \
    meld \
    hardinfo2 \
    plocate
rpm -q remmina filezilla meld rclone hardinfo2 plocate

### ----------------------------------------------------------------------------
### Move /opt contents again if any tool dropped files there
### ----------------------------------------------------------------------------

if [ -d /opt ] && [ ! -L /opt ]; then
    shopt -s dotglob nullglob
    for item in /opt/*; do
        mv "$item" /usr/lib/opt/
    done
    shopt -u dotglob nullglob
    rmdir /opt
    ln -s var/opt /opt
fi

### ----------------------------------------------------------------------------
### Cleanup
### ----------------------------------------------------------------------------

dnf5 clean all
rm -rf /var/cache/* /var/log/dnf* /var/lib/dnf/repos /run/dnf 2>/dev/null || true
