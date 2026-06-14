# ubuntu-dotfiles

Ubuntu GNOME desktop setup scripts.

## 실행 순서

각 스크립트는 따로 실행할 수 있습니다. 전체 설치 전에 내용을 먼저 확인하세요.

```bash
cd ~/ubuntu-dotfiles
```

## 1. 기본 패키지

GNOME Tweaks, Extension Manager, IBus Hangul, 설치에 필요한 도구를 설치합니다.

```bash
bash scripts/00-install-packages.sh
```

## 2. Caps Lock 한영 전환

keyd로 Caps Lock을 Hangul 키로 변환하고, IBus Hangul 전환 키를 `Hangul,Shift+space`로 설정합니다. GNOME/XKB의 Caps Lock modifier는 비활성화해서 빠르게 누를 때 대문자가 입력되는 race condition을 피합니다.

```bash
bash scripts/10-keyboard-caps-hangul.sh
```

로그아웃 후 다시 로그인하면 GNOME/IBus 세션 전체에 확실히 반영됩니다.

## 3. 폰트

Pretendard와 JetBrains Mono는 사용자 폰트 디렉터리에 설치하고, Nanum 폰트는 Ubuntu 패키지로 설치합니다.

```bash
bash scripts/20-install-fonts.sh
```

기본 sans-serif 한글 폰트는 Pretendard를 우선하도록 fontconfig를 설정합니다.

```bash
bash scripts/21-setup-fontconfig.sh
```

## 4. Nerd Font

WezTerm과 터미널 UI에 사용할 JetBrainsMono Nerd Font를 설치합니다.

```bash
bash scripts/25-install-nerdfont.sh
```

## 5. WhiteSur 테마/아이콘

WhiteSur GTK 테마와 WhiteSur 아이콘을 설치하고 GNOME 설정에 적용합니다.

```bash
bash scripts/30-install-whitesur.sh
```

## 6. Ubuntu Dock

Ubuntu Dock의 위치, 투명도, 아이콘 크기, 길이를 설정합니다.

```bash
bash scripts/35-setup-dock.sh
```

값을 바꾸려면 환경변수로 넘기세요.

```bash
DOCK_POSITION=BOTTOM DOCK_OPACITY=0.50 DOCK_ICON_SIZE=46 DOCK_HEIGHT_FRACTION=0.72 bash scripts/35-setup-dock.sh
```

Dock 배경 높이, 하단 픽셀 오프셋, 아이콘 간격은 Ubuntu Dock gsettings로 조절할 수 없어서 CSS 패치가 필요합니다. 이 패치는 Ubuntu Dock 업데이트 때 덮일 수 있습니다.

```bash
bash scripts/36-patch-dock-css.sh
```

패치 값은 스크립트 상단 변수나 환경변수로 조절할 수 있습니다.

```bash
DOCK_BOTTOM_OFFSET_PX=-2 DOCK_BACKGROUND_SPACING_PX=1 DOCK_ITEM_MARGIN_PX=1 DOCK_CONTAINER_PADDING_PX=2 DOCK_ITEM_PADDING_TOP_PX=1 DOCK_ITEM_PADDING_BOTTOM_PX=2 bash scripts/36-patch-dock-css.sh
```

## 7. WezTerm

WezTerm AppImage를 `~/.local/opt/wezterm`에 설치하고, `wezterm/wezterm.lua`를 `~/.wezterm.lua`로 링크하고, WezTerm terminfo를 설치합니다. `Ctrl+Alt+T`는 GNOME Terminal 대신 WezTerm을 실행하도록 설정합니다.

```bash
bash scripts/50-setup-wezterm.sh
```

SSH 서버에 terminfo를 설치하려면 호스트명을 인자로 넘기세요.

```bash
bash wezterm/terminfo.sh <ssh-host>
```

## 8. Node.js, Bun, Codex

Node.js LTS를 `~/.local` 아래에 설치하고, Bun과 OpenAI Codex CLI를 설치합니다. `~/dotfiles/codex/install-skills.sh`가 있으면 Codex skills도 같이 설치합니다.

```bash
bash scripts/60-install-node-bun-codex.sh
```

## 전체 실행

```bash
bash scripts/90-install-all.sh
```

## 제거 참고

이 디렉터리는 설치 스크립트만 담습니다. 설치된 항목은 다음 위치에 들어갑니다.

- Fonts: `~/.local/share/fonts`
- Themes: `~/.themes`
- Icons: `~/.icons`
- GNOME extensions: `~/.local/share/gnome-shell/extensions`
- WezTerm config link: `~/.wezterm.lua`
- WezTerm AppImage: `~/.local/opt/wezterm`
- Node.js/Codex: `~/.local`
- Bun: `~/.bun`
