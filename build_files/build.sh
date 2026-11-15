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


### 1. Store Microsoft Edge Enterprise Policy in /usr/share and link into /etc via tmpfiles.d
mkdir -p /usr/share/corp-edge
python3 - << 'PYEOF'
import json

p = "https" + "://"
policy = {
    "WebAppInstallForceList": [
        {"url": p + "outlook.cloud.microsoft/mail/", "default_launch_container": "window", "create_desktop_shortcut": True},
        {"url": p + "://microsoft.com", "default_launch_container": "window", "create_desktop_shortcut": True},
        {"url": p + "word.cloud.microsoft/", "default_launch_container": "window", "create_desktop_shortcut": True},
        {"url": p + "excel.cloud.microsoft/", "default_launch_container": "window", "create_desktop_shortcut": True},
        {"url": p + "powerpoint.cloud.microsoft/", "default_launch_container": "window", "create_desktop_shortcut": True},
        {"url": p + "m365.cloud.microsoft/", "default_launch_container": "window", "create_desktop_shortcut": True}
    ]
}

with open("/usr/share/corp-edge/m365_pwas.json", "w") as f:
    json.dump(policy, f, indent=2)
PYEOF

cat << 'EOF' > /usr/lib/tmpfiles.d/corp-edge-policy.conf
d /etc/opt/edge/policies/managed 0755 root root -
L+ /etc/opt/edge/policies/managed/m365_pwas.json - - - - /usr/share/corp-edge/m365_pwas.json
EOF

### 2. Install Microsoft Edge + ONLYOFFICE Flatpaks and expose policy folder on first boot
cat << 'EOF' > /etc/systemd/system/install-corp-flatpaks.service
[Unit]
Description=Install Corporate Flatpaks (Microsoft Edge and ONLYOFFICE)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/flatpak install -y --noninteractive flathub com.microsoft.Edge org.onlyoffice.desktopeditors
ExecStart=/usr/bin/flatpak override --system --filesystem=/etc/opt/edge/policies/managed:ro com.microsoft.Edge
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable install-corp-flatpaks.service




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
