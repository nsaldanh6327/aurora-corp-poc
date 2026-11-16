#!/bin/bash
# Sets Rexel names and icons on Edge web app shortcuts for the current user.
# Matches on the Edge app ID in the shortcut filename.
ICONS=/usr/share/rexel-icons
APPS="$HOME/.local/share/applications"

set_app() {
  local id="$1" name="$2" icon="$3"
  for f in "$APPS"/msedge-"$id"-Default.desktop; do
    [ -e "$f" ] || continue
    sed -i "s|^Name=.*|Name=$name|" "$f"
    if [ -n "$icon" ]; then
      if grep -q '^Icon=' "$f"; then
        sed -i "s|^Icon=.*|Icon=$icon|" "$f"
      else
        echo "Icon=$icon" >> "$f"
      fi
    fi
  done
}

for attempt in $(seq 1 30); do
  set_app abnfpfhjmipcnaibcolbacfhgfcmjjbn "OneDrive"          "$ICONS/onedrive.png"
  set_app cifhbcnohmdccbgoicgdjpfamggdegmo "Teams"             "$ICONS/teams.png"
  set_app emfoepeneiaokodefchogboldfmomfda "Outlook Calendar"  "$ICONS/outlook.png"
  set_app faolnafnngnfdaknnbpnkhgohbobgegn "Outlook Mail"      "$ICONS/outlook.png"
  set_app hognokfdljdhhebbnadgkbmmcofjnkca "Excel"             "$ICONS/excel.png"
  set_app mobndjgakamejfhpkpimpbabcfpcddah "PowerPoint"        "$ICONS/powerpoint.png"
  set_app pemgkhkgpeonkkcmjegkfciiikfbhbdm "OneNote"           ""
  set_app pfcfjnephabjbohkfkfneljojnjhmpjd "Word"              "$ICONS/word.png"
  set_app pcblmkhmfokgnafmeplkaoidnnmkdgdo "Rexel SharePoint"  ""
  set_app omejodamdcpkigpjficcggocapnmmggj "To Do"             ""
  sleep 10
done
