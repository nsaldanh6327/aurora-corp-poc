#!/bin/bash
set -ouex pipefail

# Copy system_files/ from the repo into /
cp -avf /ctx/system_files/. /

### ----------------------------------------------------------------------------
### /opt is a symlink to /var/opt on ostree. Use a real /opt for the RPM
### install, then move the files into the image and restore the link.
### ----------------------------------------------------------------------------

if [ -L /opt ]; then
    rm -f /opt
    mkdir /opt
fi

### Retry with increasing backoff (covers HTTP 429 from packages.microsoft.com)
retry() {
    local n=0
    until "$@"; do
        n=$((n+1))
        if [ "$n" -ge 5 ]; then
            echo "ERROR: failed after $n attempts: $*" >&2
            return 1
        fi
        echo "Attempt $n failed, retrying in $((n*60))s..."
        sleep $((n*60))
    done
}

### ----------------------------------------------------------------------------
### Vendor repos (official RPMs, vendor-signed)
### ----------------------------------------------------------------------------

cat > /etc/yum.repos.d/google-chrome.repo <<'EOF'
[google-chrome]
name=Google Chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF

cat > /etc/yum.repos.d/microsoft-edge.repo <<'EOF'
[microsoft-edge]
name=Microsoft Edge
baseurl=https://packages.microsoft.com/yumrepos/edge
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

retry dnf5 install -y --setopt=retries=10 google-chrome-stable
retry dnf5 install -y --setopt=retries=10 microsoft-edge-stable
rpm -q google-chrome-stable microsoft-edge-stable

# Remove vendor repos so browser updates come only from image rebuilds
rm -f /etc/yum.repos.d/google-chrome.repo /etc/yum.repos.d/microsoft-edge.repo

### ----------------------------------------------------------------------------
### Move browser files into the image and restore /opt -> /var/opt
### ----------------------------------------------------------------------------

mkdir -p /usr/lib/opt
for d in google microsoft; do
    if [ -d "/opt/$d" ]; then
        mv "/opt/$d" "/usr/lib/opt/$d"
    fi
done

rmdir /opt
ln -s var/opt /opt

mkdir -p /usr/lib/tmpfiles.d
cat > /usr/lib/tmpfiles.d/corp-browsers.conf <<'EOF'
d /var/opt 0755 root root -
L /var/opt/google - - - - /usr/lib/opt/google
L /var/opt/microsoft - - - - /usr/lib/opt/microsoft
EOF

### ----------------------------------------------------------------------------
### Rexel VPN: openconnect + openconnect-sso (Chrome SAML + HostScan CA rehash)
### ----------------------------------------------------------------------------

retry dnf5 install -y --setopt=retries=10 \
    openconnect \
    python3-pip \
    python3-lxml \
    python3-requests \
    python3-keyring \
    python3-pysocks \
    python3-colorama \
    python3-prompt-toolkit \
    python3-pyxdg

pip install --prefix=/usr --no-cache-dir \
    "setuptools<80" toml structlog attrs pyotp beautifulsoup4 signalrcore websockets aiohttp
pip install --prefix=/usr --no-cache-dir --no-deps openconnect-sso

# Patch openconnect-sso: native Google Chrome, stubbed PyQt6 browser module,
# and Python 3.14+ event loop fix in app.py
PY_SITES=(/usr/lib/python*/site-packages/openconnect_sso)
if [ ! -d "${PY_SITES[0]}" ]; then
    echo "ERROR: openconnect_sso package not found" >&2
    exit 1
fi

for py_site in "${PY_SITES[@]}"; do
    [ -d "$py_site" ] || continue

    install -m 0644 /usr/share/rexel-vpn/saml_authenticator.py "$py_site/saml_authenticator.py"

    cat > "$py_site/browser/__init__.py" <<'PYEOF'
from ..config import DisplayMode

class Terminated(Exception):
    pass

class Browser:
    pass
PYEOF

    # Python 3.14+: asyncio.get_event_loop() raises when no loop exists.
    python3 - "$py_site/app.py" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
helper = '''import asyncio as _aio
def _rexel_loop():
    try:
        return _aio.get_event_loop()
    except RuntimeError:
        loop = _aio.new_event_loop()
        _aio.set_event_loop(loop)
        return loop

'''
src = src.replace("asyncio.get_event_loop()", "_rexel_loop()")
open(path, "w").write(helper + src)
PYEOF
    grep -q _rexel_loop "$py_site/app.py" || { echo "ERROR: app.py patch failed" >&2; exit 1; }
done

chmod 0755 /usr/bin/rexel-vpn

# Rehash /etc/ssl/certs so Cisco HostScan cstub trusts DigiCert Trusted Root G4
csplit -s -z -f /etc/ssl/certs/ca- -b "%03d.pem" \
    /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem \
    '/-----BEGIN CERTIFICATE-----/' '{*}'
openssl rehash /etc/ssl/certs

### ----------------------------------------------------------------------------
### Managed policies: real files in /etc/opt (supported by bootc lint)
### ----------------------------------------------------------------------------

M365_POLICY=/tmp/m365_pwas.json
cat > "$M365_POLICY" <<'EOF'
{
  "WebAppInstallForceList": [
    {"url": "https://outlook.cloud.microsoft/mail/", "fallback_app_name": "Outlook", "default_launch_container": "window", "create_desktop_shortcut": true},
    {"url": "https://teams.microsoft.com/v2/", "fallback_app_name": "Teams", "default_launch_container": "window", "create_desktop_shortcut": true},
    {"url": "https://onedrive.live.com/", "fallback_app_name": "OneDrive", "default_launch_container": "window", "create_desktop_shortcut": true},
    {"url": "https://word.cloud.microsoft/", "fallback_app_name": "Word", "default_launch_container": "window", "create_desktop_shortcut": true},
    {"url": "https://excel.cloud.microsoft/", "fallback_app_name": "Excel", "default_launch_container": "window", "create_desktop_shortcut": true},
    {"url": "https://powerpoint.cloud.microsoft/", "fallback_app_name": "PowerPoint", "default_launch_container": "window", "create_desktop_shortcut": true}
  ]
}
EOF

# Fail the build if the JSON is invalid
python3 -m json.tool "$M365_POLICY" > /dev/null

for dir in /etc/opt/edge/policies/managed /etc/opt/chrome/policies/managed; do
    mkdir -p "$dir"
    install -m 0644 "$M365_POLICY" "$dir/m365_pwas.json"
done
rm -f "$M365_POLICY"

### ----------------------------------------------------------------------------
### Edge web app launchers (fixed IDs so they can be pinned)
### ----------------------------------------------------------------------------

EDGE_APPS=(
  "outlook|Outlook|https://outlook.cloud.microsoft/mail/"
  "teams|Teams|https://teams.microsoft.com/v2/"
  "onedrive|OneDrive|https://onedrive.live.com/"
  "word|Word|https://word.cloud.microsoft/"
  "excel|Excel|https://excel.cloud.microsoft/"
  "powerpoint|PowerPoint|https://powerpoint.cloud.microsoft/"
)

for entry in "${EDGE_APPS[@]}"; do
    IFS='|' read -r id name url <<< "$entry"
    cat > "/usr/share/applications/rexel-${id}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${name}
Exec=/usr/bin/microsoft-edge-stable --app=${url} --no-first-run
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
### ONLYOFFICE: Flatpak preinstall on first boot
### ----------------------------------------------------------------------------

mkdir -p /usr/share/flatpak/preinstall.d /usr/share/flatpak/remotes.d
cat > /usr/share/flatpak/remotes.d/flathub.flatpakrepo <<'EOF'
[Flatpak Repo]
Title=Flathub
Url=https://dl.flathub.org/repo/
Homepage=https://flathub.org/
EOF
cat > /usr/share/flatpak/preinstall.d/onlyoffice.preinstall <<'EOF'
[Flatpak Preinstall org.onlyoffice.desktopeditors]
Branch=stable
EOF

### ----------------------------------------------------------------------------
### Cleanup: remove runtime and dnf state that lint flags
### ----------------------------------------------------------------------------

dnf5 clean all
rm -rf /var/cache/* /var/log/dnf* /var/lib/dnf/repos /run/dnf 2>/dev/null || true
