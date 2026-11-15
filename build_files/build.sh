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

### Install Google Chrome safely for bootc/ostree (/opt -> /usr/lib/opt)
mkdir -p /var/opt /usr/lib/opt
cat << 'EOF' > /etc/yum.repos.d/google-chrome.repo
[google-chrome]
name=google-chrome
baseurl=https://google.com
enabled=1
gpgcheck=1
gpgkey=https://google.com
EOF
dnf5 install -y google-chrome-stable

# Move Chrome from /var/opt to /usr/lib/opt so it survives image sealing
mv /var/opt/google /usr/lib/opt/google
cat << 'EOF' > /usr/lib/tmpfiles.d/google-chrome.conf
L /var/opt/google - - - - /usr/lib/opt/google
EOF


# 2. Pre-configure Chrome Enterprise Policy for Microsoft 365 PWAs
mkdir -p /etc/opt/chrome/policies/managed
cat << 'M365_POLICY' > /etc/opt/chrome/policies/managed/m365_pwas.json
{
  "WebAppInstallForceList": [
    {
      "url": "https://outlook.office.com/mail/",
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    },
    {
      "url": "https://teams.microsoft.com/",
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    },
    {
      "url": "https://www.office.com/",
      "default_launch_container": "window",
      "create_desktop_shortcut": true
    }
  ]
}
M365_POLICY

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
