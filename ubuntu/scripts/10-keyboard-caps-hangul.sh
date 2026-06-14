#!/usr/bin/env bash

set -euo pipefail

if ! systemctl list-unit-files keyd.service >/dev/null 2>&1; then
	echo "keyd is not installed. Install it first: sudo apt install keyd" >&2
	exit 1
fi

keyd_config="$(mktemp)"
cleanup() {
	rm -f "$keyd_config"
}
trap cleanup EXIT

cat >"$keyd_config" <<'EOF'
[ids]
*

[main]
capslock = hangeul
EOF

sudo install -D -m 0644 "$keyd_config" /etc/keyd/default.conf
sudo systemctl enable keyd
sudo systemctl restart keyd

# IBus Hangul receives Hangul from keyd instead of the physical Caps Lock key.
gsettings set org.freedesktop.ibus.engine.hangul switch-keys 'Hangul,Shift+space'
gsettings set org.freedesktop.ibus.engine.hangul initial-input-mode 'hangul'
gsettings set org.freedesktop.ibus.engine.hangul disable-latin-mode false

# Ensure the Hangul engine is available in GNOME input sources.
sources="$(gsettings get org.gnome.desktop.input-sources sources)"
if [[ "$sources" != *"('ibus', 'hangul')"* ]]; then
	gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'kr+kr104'), ('ibus', 'hangul')]"
fi

# Disable the Caps Lock modifier in GNOME/XKB. keyd handles Caps Lock before it
# reaches GNOME, which avoids the Wayland/XKB/IBus race condition.
current_options="$(gsettings get org.gnome.desktop.input-sources xkb-options)"
new_options="$(
	python3 - "$current_options" <<'PY'
import ast
import sys

raw = sys.argv[1]
options = [] if raw == "@as []" else ast.literal_eval(raw)
options = [item for item in options if not item.startswith("caps:")]
options.append("caps:none")
print(str(options))
PY
)"
gsettings set org.gnome.desktop.input-sources xkb-options "$new_options"

# Apply the same modifier disable immediately for X11 sessions.
xkb_option_list="$(
	python3 - "$new_options" <<'PY'
import ast
import sys

print(",".join(ast.literal_eval(sys.argv[1])))
PY
)"
setxkbmap -option 2>/dev/null || true
if [[ -n "$xkb_option_list" ]]; then
	setxkbmap -option "$xkb_option_list" 2>/dev/null || true
fi
xset -led named "Caps Lock" 2>/dev/null || true

# Reload IBus settings when available.
ibus restart 2>/dev/null || true
sleep 1
ibus engine hangul 2>/dev/null || true

echo "Caps Lock now sends Hangul through keyd, and IBus Hangul uses Hangul with Shift+Space fallback."
