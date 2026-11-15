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


### Create native KDE desktop app launchers for Microsoft 365 (opens in standalone Chrome app windows)
mkdir -p /usr/share/applications

create_m365_app() {
  local id="$1"
  local name="$2"
  local url="$3"
  cat << EOF > "/usr/share/applications/corp-${id}.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=${name}
Comment=Microsoft ${name} Web App
Exec=/usr/lib/opt/google/chrome/google-chrome --app=${url}
Icon=web-browser
Categories=Office;Network;
Terminal=false
StartupNotify=true
EOF
}

p="https"
create_m365_app "outlook" "Outlook" "${p}://://office.com"
create_m365_app "teams" "Microsoft Teams" "${p}://://microsoft.com"
create_m365_app "word" "Microsoft Word" "${p}://://office.com"
create_m365_app "excel" "Microsoft Excel" "${p}://://office.com"
create_m365_app "powerpoint" "Microsoft PowerPoint" "${p}://://office.com"
create_m365_app "onedrive" "OneDrive" "${p}://m365.cloud.microsoft/onedrive"






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
