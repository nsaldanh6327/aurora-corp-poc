#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y tmux

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket

### ----------------------------------------------------------------------------
### ENTERPRISE CUSTOMIZATIONS: CHROME, M365 PWAS, AND ONLYOFFICE
### ----------------------------------------------------------------------------

mkdir -p /var/opt /usr/lib/opt
dnf5 install -y fedora-workstation-repositories
dnf5 config-manager setopt google-chrome.enabled=1
dnf5 install -y google-chrome-stable
mv /var/opt/google /usr/lib/opt/google
printf "L /var/opt/google - - - - /usr/lib/opt/google\n" > /usr/lib/tmpfiles.d/google-chrome.conf

### Generate crisp M365 app icons locally using Python (no external URLs needed)
mkdir -p /usr/share/pixmaps/m365
python3 - << 'PYEOF'
import zlib, struct

def make_png(path, r, g, b):
    w = h = 192
    raw = b"".join(b"\x00" + bytes([r, g, b]) * w for _ in range(h))
    def chunk(tag, data):
        return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", zlib.crc32(tag + data) & 0xffffffff)
    ihdr = struct.pack("!IIBBBBB", w, h, 8, 2, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))

make_png("/usr/share/pixmaps/m365/outlook.png", 0, 120, 212)     # Outlook Blue
make_png("/usr/share/pixmaps/m365/word.png", 43, 87, 154)        # Word Blue
make_png("/usr/share/pixmaps/m365/excel.png", 33, 115, 70)       # Excel Green
make_png("/usr/share/pixmaps/m365/powerpoint.png", 183, 71, 42)  # PowerPoint Orange
make_png("/usr/share/pixmaps/m365/onedrive.png", 9, 74, 178)     # OneDrive Navy
PYEOF

### Configure Chrome Enterprise Policy for all 6 Microsoft 365 PWAs
mkdir -p /etc/opt/chrome/policies/managed
H="https"
cat << EOF > /etc/opt/chrome/policies/managed/m365_pwas.json
{
  "WebAppInstallForceList": [
    {
      "url": "${H}://://office.com",
      "custom_name": "Outlook",
      "custom_icon": { "url": "file:///usr/share/pixmaps/m365/outlook.png" },
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    },
    {
      "url": "${H}://://microsoft.com",
      "custom_name": "Microsoft Teams",
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    },
    {
      "url": "${H}://://office.com",
      "custom_name": "Microsoft Word",
      "custom_icon": { "url": "file:///usr/share/pixmaps/m365/word.png" },
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    },
    {
      "url": "${H}://://office.com",
      "custom_name": "Microsoft Excel",
      "custom_icon": { "url": "file:///usr/share/pixmaps/m365/excel.png" },
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    },
    {
      "url": "${H}://://office.com",
      "custom_name": "Microsoft PowerPoint",
      "custom_icon": { "url": "file:///usr/share/pixmaps/m365/powerpoint.png" },
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    },
    {
      "url": "${H}://m365.cloud.microsoft/onedrive",
      "custom_name": "OneDrive",
      "custom_icon": { "url": "file:///usr/share/pixmaps/m365/onedrive.png" },
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    }
  ]
}
EOF





# 3. Pre-install ONLYOFFICE Desktop Editors via Flatpak on first boot
cat << 'FLATPAK_SVC' > /etc/systemd/system/install-corp-flatpaks.service
[Unit]
Description=Install Corporate Flatpaks (ONLYOFFICE)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/flatpak install -y --noninteractive flathub org.onlyoffice.desktopeditors
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
FLATPAK_SVC
systemctl enable install-corp-flatpaks.service
