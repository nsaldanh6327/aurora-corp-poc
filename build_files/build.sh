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

### Download Microsoft 365 icons locally into the OS image
mkdir -p /usr/share/pixmaps/m365
curl -sL "https://office.net" -o /usr/share/pixmaps/m365/outlook.png
curl -sL "https://office.net" -o /usr/share/pixmaps/m365/word.png
curl -sL "https://office.net" -o /usr/share/pixmaps/m365/excel.png
curl -sL "https://office.net" -o /usr/share/pixmaps/m365/powerpoint.png
curl -sL "https://office.net" -o /usr/share/pixmaps/m365/onedrive.png

### Pre-configure Chrome Enterprise Policy for all Microsoft 365 PWAs
mkdir -p /etc/opt/chrome/policies/managed
cat << 'EOF' > /etc/opt/chrome/policies/managed/m365_pwas.json
{
  "WebAppInstallForceList": [
    {
      "url": "https://office.com",
      "custom_name": "Outlook",
      "custom_icon": {
        "url": "file:///usr/share/pixmaps/m365/outlook.png"
      },
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    },
    {
      "url": "https://microsoft.com",
      "custom_name": "Microsoft Teams",
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    },
    {
      "url": "https://office.com",
      "custom_name": "Microsoft Word",
      "custom_icon": {
        "url": "file:///usr/share/pixmaps/m365/word.png"
      },
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    },
    {
      "url": "https://office.com",
      "custom_name": "Microsoft Excel",
      "custom_icon": {
        "url": "file:///usr/share/pixmaps/m365/excel.png"
      },
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    },
    {
      "url": "https://office.com",
      "custom_name": "Microsoft PowerPoint",
      "custom_icon": {
        "url": "file:///usr/share/pixmaps/m365/powerpoint.png"
      },
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    },
    {
      "url": "https://live.com",
      "custom_name": "OneDrive",
      "custom_icon": {
        "url": "file:///usr/share/pixmaps/m365/onedrive.png"
      },
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
