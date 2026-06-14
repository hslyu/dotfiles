#!/usr/bin/env bash

set -euo pipefail

schema="org.gnome.shell.extensions.dash-to-dock"

if ! gsettings list-schemas | grep -qx "$schema"; then
    echo "Missing $schema. Ubuntu Dock/Dash to Dock is not available." >&2
    exit 1
fi

dock_position="${DOCK_POSITION:-BOTTOM}"
dock_opacity="${DOCK_OPACITY:-0.60}"
dock_icon_size="${DOCK_ICON_SIZE:-40}"
dock_height_fraction="${DOCK_HEIGHT_FRACTION:-0.4}"

gsettings set "$schema" dock-position "$dock_position"
gsettings set "$schema" transparency-mode "FIXED"
gsettings set "$schema" customize-alphas true
gsettings set "$schema" background-opacity "$dock_opacity"
gsettings set "$schema" min-alpha "$dock_opacity"
gsettings set "$schema" max-alpha "$dock_opacity"
gsettings set "$schema" extend-height false
gsettings set "$schema" height-fraction "$dock_height_fraction"
gsettings set "$schema" dash-max-icon-size "$dock_icon_size"
gsettings set "$schema" icon-size-fixed true
gsettings set "$schema" custom-theme-shrink true
gsettings set "$schema" always-center-icons true

echo "Dock configured: position=${dock_position}, opacity=${dock_opacity}, icon_size=${dock_icon_size}, height_fraction=${dock_height_fraction}"
