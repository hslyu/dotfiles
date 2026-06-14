#!/usr/bin/env bash

set -euo pipefail

fontconfig_dir="$HOME/.config/fontconfig"
fontconfig_path="$fontconfig_dir/fonts.conf"

mkdir -p "$fontconfig_dir"

cat >"$fontconfig_path" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Pretendard</family>
      <family>Noto Sans CJK KR</family>
    </prefer>
  </alias>
</fontconfig>
EOF

fc-cache -f

echo "Fontconfig written to $fontconfig_path"
