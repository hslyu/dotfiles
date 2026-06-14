#!/usr/bin/env bash

set -euo pipefail

css_path="/usr/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com/stylesheet.css"
backup_path="${css_path}.backup.$(date +%Y%m%d-%H%M%S)"

dock_bottom_offset_px="${DOCK_BOTTOM_OFFSET_PX:--10}"
dock_background_radius_px="${DOCK_BACKGROUND_RADIUS_PX:-10}"
dock_background_spacing_px="${DOCK_BACKGROUND_SPACING_PX:-1}"
dock_separator_margin_px="${DOCK_SEPARATOR_MARGIN_PX:-0}"
dock_container_padding_px="${DOCK_CONTAINER_PADDING_PX:-2}"
dock_item_margin_px="${DOCK_ITEM_MARGIN_PX:-1}"
dock_item_padding_x_px="${DOCK_ITEM_PADDING_X_PX:-5}"
dock_item_padding_top_px="${DOCK_ITEM_PADDING_TOP_PX:-1}"
dock_item_padding_bottom_px="${DOCK_ITEM_PADDING_BOTTOM_PX:-2}"

if [[ ! -f "$css_path" ]]; then
    echo "Missing $css_path" >&2
    exit 1
fi

for value in \
    "$dock_bottom_offset_px" \
    "$dock_background_radius_px" \
    "$dock_background_spacing_px" \
    "$dock_separator_margin_px" \
    "$dock_container_padding_px" \
    "$dock_item_margin_px" \
    "$dock_item_padding_x_px" \
    "$dock_item_padding_top_px" \
    "$dock_item_padding_bottom_px"; do
    if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
        echo "Pixel values must be integers, got: $value" >&2
        exit 1
    fi
done

tmp_path="$(mktemp)"
cleanup() {
    rm -f "$tmp_path"
}
trap cleanup EXIT

python3 - "$css_path" "$tmp_path" \
    "$dock_bottom_offset_px" \
    "$dock_background_radius_px" \
    "$dock_background_spacing_px" \
    "$dock_separator_margin_px" \
    "$dock_container_padding_px" \
    "$dock_item_margin_px" \
    "$dock_item_padding_x_px" \
    "$dock_item_padding_top_px" \
    "$dock_item_padding_bottom_px" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
(
    bottom_offset,
    background_radius,
    background_spacing,
    separator_margin,
    container_padding,
    item_margin,
    item_padding_x,
    item_padding_top,
    item_padding_bottom,
) = sys.argv[3:]
text = source.read_text()

patches = [
    (
        r"(#dashtodockContainer\.bottom\.shrink #dash \.dash-background \{\n"
        r"\s+margin: 0;\n)"
        r"\s+margin-bottom: -?\d+px;",
        rf"\g<1>    margin-bottom: {bottom_offset}px;",
    ),
    (
        r"(#dashtodockContainer\.bottom\.shrink #dash \.dash-background \{[\s\S]*?"
        r"border-radius: )\d+px;",
        rf"\g<1>{background_radius}px;",
    ),
    (
        r"(#dashtodockContainer\.bottom\.shrink #dash \.dash-background \{[\s\S]*?"
        r"spacing: )\d+px;",
        rf"\g<1>{background_spacing}px;",
    ),
    (
        r"(#dashtodockContainer\.bottom\.shrink #dash \.dash-separator \{[\s\S]*?"
        r"margin: 0 )\d+px;",
        rf"\g<1>{separator_margin}px;",
    ),
    (
        r"(#dashtodockContainer\.bottom\.shrink #dash \.dash-separator \{[\s\S]*?"
        r"margin-bottom: )-?\d+px;",
        rf"\g<1>{bottom_offset}px;",
    ),
    (
        r"(#dashtodockContainer\.bottom\.shrink #dash #dashtodockDashContainer \{\n"
        r"\s+padding: )\d+px;",
        rf"\g<1>{container_padding}px;",
    ),
    (
        r"(#dashtodockContainer\.bottom\.shrink #dash \.dash-item-container \{\n"
        r"\s+/\* Disable all margins defined upstream, we handle them here \*/\n"
        r"\s+margin: 0 )\d+px;",
        rf"\g<1>{item_margin}px;",
    ),
    (
        r"(#dashtodockContainer\.bottom\.shrink #dash \.dash-item-container \.app-well-app,"
        r"\n\s+#dashtodockContainer\.bottom\.shrink #dash \.dash-item-container \.show-apps,"
        r"\n\s+#dashtodockContainer\.bottom\.shrink #dash \.dash-item-container \.overview-tile \{\n"
        r"\s+padding: )\d+px \d+px;\n"
        r"\s+padding-bottom: -?\d+px;\n"
        r"\s+padding-top: -?\d+px;",
        rf"\g<1>{item_padding_x}px {item_padding_x}px;\n      padding-bottom: {item_padding_bottom}px;\n      padding-top: {item_padding_top}px;",
    ),
]

for pattern, replacement in patches:
    text, count = re.subn(pattern, replacement, text, count=1)
    if count != 1:
        raise SystemExit(f"Expected one CSS match, got {count}: {pattern}")

target.write_text(text)
PY

sudo cp "$css_path" "$backup_path"
sudo install -m 0644 "$tmp_path" "$css_path"

echo "Patched Ubuntu Dock CSS."
echo "Backup: $backup_path"
echo "Values: bottom_offset=${dock_bottom_offset_px}px, spacing=${dock_background_spacing_px}px, item_margin=${dock_item_margin_px}px, container_padding=${dock_container_padding_px}px, item_padding_top=${dock_item_padding_top_px}px, item_padding_bottom=${dock_item_padding_bottom_px}px"

if command -v gnome-extensions >/dev/null 2>&1; then
    if gnome-extensions info ubuntu-dock@ubuntu.com >/dev/null 2>&1; then
        gnome-extensions disable ubuntu-dock@ubuntu.com || true
        sleep 1
        gnome-extensions enable ubuntu-dock@ubuntu.com || true
        sleep 1
    fi
fi

if gnome-extensions info ubuntu-dock@ubuntu.com 2>/dev/null | grep -q "State: ACTIVE"; then
    echo "Ubuntu Dock extension reloaded."
else
    echo "Ubuntu Dock CSS patched, but the extension did not reload cleanly."
    echo "Log out and back in to force GNOME Shell to reload the stylesheet."
fi
