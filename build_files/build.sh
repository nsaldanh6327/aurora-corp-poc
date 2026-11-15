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

### Store Chrome Enterprise Policy in /usr/share and link into /etc via tmpfiles.d
mkdir -p /usr/share/corp-chrome
python3 - << 'PYEOF'
import json

p = "https" + "://"
policy = {
    "WebAppInstallForceList": [
        {
            "url": p + "://office.com",
            "custom_name": "Outlook",
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
            "url": p + "://office.com",
            "custom_name": "Microsoft Word",
            "default_launch_container": "window",
            "create_desktop_shortcut": True
        },
        {
            "url": p + "://office.com",
            "custom_name": "Microsoft Excel",
            "default_launch_container": "window",
            "create_desktop_shortcut": True
        },
        {
            "url": p + "://office.com",
            "custom_name": "Microsoft PowerPoint",
            "default_launch_container": "window",
            "create_desktop_shortcut": True
        },
        {
            "url": p + "://live.com",
            "custom_name": "OneDrive",
            "default_launch_container": "window",
            "create_desktop_shortcut": True
        }
    ]
}

with open("/usr/share/corp-chrome/m365_pwas.json", "w") as f:
    json.dump(policy, f, indent=2)
PYEOF

cat << 'EOF' > /usr/lib/tmpfiles.d/corp-chrome-policy.conf
d /etc/opt/chrome/policies/managed 0755 root root -
L+ /etc/opt/chrome/policies/managed/m365_pwas.json - - - - /usr/share/corp-chrome/m365_pwas.json
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
