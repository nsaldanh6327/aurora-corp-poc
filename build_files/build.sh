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

### Vendor repos (official RPMs, vendor-signed)

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

# Retry with increasing backoff (covers HTTP 429 from packages.microsoft.com)
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
### KDE taskbar defaults: Plasma task manager launchers (system-wide default)
### Only the "launchers" entry is changed. Fails the build if it isn't found.
### ----------------------------------------------------------------------------

TM_XML=/usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml
python3 - "$TM_XML" <<'PYEOF'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()
ns = {"k": "http://www.kde.org/standards/kcfg/1.0"}

found = False
for entry in root.iter("{http://www.kde.org/standards/kcfg/1.0}entry"):
    if entry.get("name") == "launchers":
        default = entry.find("{http://www.kde.org/standards/kcfg/1.0}default")
        if default is None:
            default = ET.SubElement(entry, "{http://www.kde.org/standards/kcfg/1.0}default")
        default.text = ",".join([
            "applications:google-chrome.desktop",
            "applications:microsoft-edge.desktop",
        ])
        found = True

if not found:
    sys.exit("ERROR: 'launchers' entry not found in " + path)

tree.write(path, xml_declaration=True, encoding="UTF-8")
PYEOF

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
