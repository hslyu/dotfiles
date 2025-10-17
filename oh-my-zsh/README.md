# light-shell oh-my-zsh

우분투에서 zsh/oh-my-zsh을 가볍게 쓰기 위한 최소 구성입니다.

## 구성 요소
- `light-shell/oh-my-zsh/.zshrc` : 순정 oh-my-zsh를 기준으로 한 슬림 설정
- `light-shell/oh-my-zsh/custom/` : 환경 변수, alias, 함수, 플러그인 등 사용자 스크립트
- `light-shell/oh-my-zsh/scripts/basedpyright-tools/` : `pymv`에서 사용하는 basedpyright LSP 유틸
- `light-shell/oh-my-zsh/starship.toml` : Starship 프롬프트 테마
- `light-shell/oh-my-zsh/launch-zsh-in-bash.sh` : bash 로그인 시 자동으로 zsh를 실행하는 보조 스크립트
- `light-shell/oh-my-zsh/install-installers.sh` : Node/Bun/uv/Miniforge/rustup 등을 사용자 디렉터리에 설치하는 부트스트랩 스크립트
- `light-shell/oh-my-zsh/zsh-local-install.sh` : 로컬에 zsh를 빌드/설치하는 유틸리티

## 설치/연결 예시
```bash
mkdir -p ~/.config/oh-my-zsh
ln -s ~/dotfiles/light-shell/oh-my-zsh/.zshrc ~/.zshrc
ln -s ~/dotfiles/light-shell/oh-my-zsh/custom ~/.config/oh-my-zsh/custom
ln -s ~/dotfiles/light-shell/oh-my-zsh/starship.toml ~/.config/starship.toml
```

플러그인을 내려받으려면 서브모듈을 초기화하세요.
```bash
cd ~/dotfiles
git submodule update --init --remote light-shell/oh-my-zsh/custom/plugins
```

필요한 바이너리는 다음 스크립트로 설치할 수 있습니다.
```bash
~/dotfiles/light-shell/oh-my-zsh/apps-local-install.sh
```

스크립트는 bun 설치가 필요하면 자동으로 설치하고, basedpyright 유틸리티 디렉터리에서 `bun install`까지 실행해 줍니다.

추가로 zsh 및 런타임들을 준비하려면 아래 스크립트들을 상황에 맞게 실행하세요.
- `~/dotfiles/light-shell/oh-my-zsh/install-installers.sh` : Node, Bun, uv, Miniforge(Conda), rustup 등을 설치
- `~/dotfiles/light-shell/oh-my-zsh/zsh-local-install.sh` : 필요 시 최신 zsh를 `~/.local/bin/zsh`에 빌드 설치
