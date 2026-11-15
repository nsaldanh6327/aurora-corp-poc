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


### Generate Chrome Enterprise Policy for M365 PWAs (zero external URLs or file:// paths)
mkdir -p /etc/opt/chrome/policies/managed
python3 - << 'PYEOF'
import json, zlib, struct, base64

def png_data_uri(r, g, b):
    w = h = 192
    raw = b"".join(b"\x00" + bytes([r, g, b]) * w for _ in range(h))
    def chunk(tag, data):
        return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", zlib.crc32(tag + data) & 0xffffffff)
    ihdr = struct.pack("!IIBBBBB", w, h, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    return "data:image/png;base64," + base64.b64encode(png).decode("ascii")

p = "https" + "://"
policy = {
    "WebAppInstallForceList": [
        {
            "url": p + "outlook.cloud.microsoft/mail/",
            "custom_name": "Outlook",
            "custom_icon": {"url": png_data_uri(0, 120, 212)},
            "default_launch_container": "window",
            "create_desktop_shortcut": True
        },
        {
            "url": p + "://microsoft.com",
            "custom_name": "Microsoft Teams",
            "default_launch_container": "window",
            "create_desktop_shortcut": True
        },
        {
            "url": p + "word.cloud.microsoft/",
            "custom_name": "Microsoft Word",
            "custom_icon": {"url": png_data_uri(43, 87, 154)},
            "default_launch_container": "window",
            "create_desktop_shortcut": True
        },
        {
            "url": p + "excel.cloud.microsoft/",
            "custom_name": "Microsoft Excel",
            "custom_icon": {"url": png_data_uri(33, 115, 70)},
            "default_launch_container": "window",
            "create_desktop_shortcut": True
        },
        {
            "url": p + "powerpoint.cloud.microsoft/",
            "custom_name": "Microsoft PowerPoint",
            "custom_icon": {"url": png_data_uri(183, 71, 42)},
            "default_launch_container": "window",
            "create_desktop_shortcut": True
        },
        {
            "url": p + "://live.com",
            "custom_name": "OneDrive",
            "custom_icon": {"url": png_data_uri(9, 74, 178)},
            "default_launch_container": "window",
            "create_desktop_shortcut": True
        }
    ]
}

with open("/etc/opt/chrome/policies/managed/m365_pwas.json", "w") as f:
    json.dump(policy, f, indent=2)
PYEOF





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
