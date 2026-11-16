#!/bin/bash
# Sets Rexel icons on Edge web app shortcuts for the current user.
ICONS=/usr/share/rexel-icons
APPS="$HOME/.local/share/applications"

for attempt in $(seq 1 30); do
  for f in "$APPS"/msedge-*.desktop; do
    [ -e "$f" ] || continue
    name=$(grep -m1 '^Name=' "$f" | cut -d= -f2-)
    case "$name" in
      "Outlook Mail"|"Outlook Calendar") icon="$ICONS/outlook.png" ;;
      "Teams")                           icon="$ICONS/teams.png" ;;
      "Word")                            icon="$ICONS/word.png" ;;
      "Excel")                           icon="$ICONS/excel.png" ;;
      "PowerPoint")                      icon="$ICONS/powerpoint.png" ;;
      "OneDrive")                        icon="$ICONS/onedrive.png" ;;
      *) continue ;;
    esac
    if grep -q '^Icon=' "$f"; then
      sed -i "s|^Icon=.*|Icon=$icon|" "$f"
    else
      echo "Icon=$icon" >> "$f"
    fi
  done
  sleep 10
done
