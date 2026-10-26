#!/bin/bash
# Mac bootstrap script. Usage: bash setup-mac.sh
# Each step is independent; failures are collected and reported at the end.

ADDITIONALS_DIR="$HOME/Yashu/additionals"
TS="$(date +%Y%m%d%H%M%S)"
DONE=()
SKIPPED=()
FAILED=()
SKIP=100  # return code meaning "already installed"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

step() {
  local name="$1"; shift
  log "$name"
  "$@"
  local rc=$?
  if [ $rc -eq 0 ]; then
    DONE+=("$name")
  elif [ $rc -eq $SKIP ]; then
    SKIPPED+=("$name")
    echo "Already installed, skipping."
  else
    FAILED+=("$name")
    printf '\033[1;31m[FAILED] %s\033[0m\n' "$name"
  fi
}

have_cmd() { command -v "$1" &>/dev/null; }
have_app() { [ -d "/Applications/$1.app" ] || [ -d "$HOME/Applications/$1.app" ]; }

load_brew() {
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

brew_formula() { brew list --formula "$1" &>/dev/null && return $SKIP; brew install "$1"; }

# Keep cask app details in additionals even after Homebrew's cache is cleared.
record_cask_app() {
  local cask="$1" app="$2" install_source="$3" path version caskroom_path
  if [ -d "/Applications/$app.app" ]; then
    path="/Applications/$app.app"
  elif [ -d "$HOME/Applications/$app.app" ]; then
    path="$HOME/Applications/$app.app"
  else
    echo "Cannot record $app: installed app not found." >&2
    return 1
  fi
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$path/Contents/Info.plist" 2>/dev/null)" ||
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$path/Contents/Info.plist")" || return 1
  if [ -z "$version" ]; then
    echo "Cannot record $app: installed version is empty." >&2
    return 1
  fi
  caskroom_path="$(brew --prefix)/Caskroom/$cask" || return 1
  mkdir -p "$ADDITIONALS_DIR/$cask" || return 1
  printf 'App: %s\nVersion: %s\nInstalled through: %s\nInstalled path: %s\nHomebrew Caskroom path: %s\n' \
    "$app" "$version" "$install_source" "$path" "$caskroom_path" \
    > "$ADDITIONALS_DIR/$cask/installed.txt"
}

brew_cask() {
  local cask="$1" app="$2"
  if brew list --cask "$cask" &>/dev/null; then
    record_cask_app "$cask" "$app" "Homebrew cask ($cask)" || return 1
    return $SKIP
  fi
  if have_app "$app"; then
    record_cask_app "$cask" "$app" "Pre-existing app; source unknown" || return 1
    return $SKIP
  fi
  brew install --cask "$cask" || return 1
  record_cask_app "$cask" "$app" "Homebrew cask ($cask)"
}

# ---------------------------------------------------------------------------
# 1. Xcode Command Line Tools (provides git, needed by Homebrew)
# ---------------------------------------------------------------------------
install_clt() {
  xcode-select -p &>/dev/null && return $SKIP
  xcode-select --install
  echo "Complete the Command Line Tools installer dialog; waiting..."
  for _ in $(seq 1 180); do
    xcode-select -p &>/dev/null && return 0
    sleep 10
  done
  return 1
}

# ---------------------------------------------------------------------------
# 2. Homebrew
# ---------------------------------------------------------------------------
install_homebrew() {
  load_brew
  have_cmd brew && return $SKIP
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
  load_brew
  have_cmd brew
}

# ---------------------------------------------------------------------------
# 3. Git + aliases
# ---------------------------------------------------------------------------
install_git() { have_cmd git && return $SKIP; brew_formula git; }

config_git() {
  git config --global alias.cbs '!f() { git branch $1 && git switch $1; }; f' &&
  git config --global alias.sp '!f() { git switch $1 && git pull; }; f' &&
  git config --global alias.co 'checkout' &&
  git config --global alias.fa 'fetch --all' &&
  git config --global alias.cm 'commit -m' &&
  git config --global alias.fpwl 'push --force-with-lease' &&
  git config --global alias.fp 'push -f' &&
  git config --global alias.amend 'commit --amend --no-edit' &&
  git config --global alias.s 'stash' &&
  git config --global alias.hr 'reset --hard' &&
  git config --global alias.bl "!git for-each-ref --sort='-authordate' --format='%(authordate)%09%(objectname:short)%09%(refname)' refs/heads | sed -e 's-refs/heads/--'" &&
  git config --global alias.ls 'log --pretty=format:"%C(yellow)%h\ %ad%Cred%d\ %Creset%s%Cblue\ [%cn]" --decorate --date=long' &&
  git config --global alias.ll 'log --pretty=format:"%C(yellow)%h\ %ad%Cred%d\ %Creset%s%Cblue\ [%cn]" --decorate --date=long --numstat' &&
  git config --global alias.pull 'pull --rebase' &&
  git config --global push.autoSetupRemote true
}

# ---------------------------------------------------------------------------
# 4. Docker + images
# ---------------------------------------------------------------------------
install_docker() {
  brew_cask docker-desktop Docker
  local rc=$?
  if [ "$rc" -eq 0 ] || [ "$rc" -eq "$SKIP" ]; then
    return "$rc"
  fi
  brew_cask docker Docker
}

pull_docker_images() {
  local images=(mysql:8.0 postgres:16 redis mongo) missing=() img
  have_cmd docker || return 1
  for img in "${images[@]}"; do
    docker image inspect "$img" &>/dev/null || missing+=("$img")
  done
  # image inspect also fails when the daemon is down, so this only skips when it's up
  [ ${#missing[@]} -eq 0 ] && return $SKIP

  if ! docker info &>/dev/null; then
    open -a Docker || return 1
    echo "Waiting for Docker daemon (accept the license dialog if shown)..."
    for _ in $(seq 1 60); do
      docker info &>/dev/null && break
      sleep 5
    done
  fi
  docker info &>/dev/null || return 1
  local ok=0
  for img in "${missing[@]}"; do
    if docker image inspect "$img" &>/dev/null; then
      echo "$img already present"
    else
      docker pull "$img" || ok=1
    fi
  done
  return $ok
}

# ---------------------------------------------------------------------------
# 5. Ollama
# ---------------------------------------------------------------------------
install_ollama() {
  { have_cmd ollama || have_app Ollama; } && return $SKIP
  brew_formula ollama
}

# /usr/bin/python3 is only an Xcode stub, so check for the Homebrew one
install_python() {
  [ -x "$(brew --prefix 2>/dev/null)/bin/python3" ] && return $SKIP
  brew_formula python
}

# ---------------------------------------------------------------------------
# 6. SSH config (+ tools used by ProxyCommand entries)
# ---------------------------------------------------------------------------
config_ssh() {
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" || return 1
  [ -f "$HOME/.ssh/config" ] && cp "$HOME/.ssh/config" "$HOME/.ssh/config.bak.$TS"
  cat > "$HOME/.ssh/config" <<'EOF'
Host 192.168.29.111
  HostName 192.168.29.111
  User jacksparrow

Host 172.19.189.179
  HostName 172.19.189.179
  User jacksparrow

Host ssh.yashu.fun
    ProxyCommand cloudflared access ssh --hostname %h
    User jacksparrow

EOF
  chmod 600 "$HOME/.ssh/config"
}

install_cloudflared() { have_cmd cloudflared && return $SKIP; brew_formula cloudflared; }
install_awscli()      { have_cmd aws && return $SKIP; brew_formula awscli; }

# ---------------------------------------------------------------------------
# 7. Zsh: oh-my-zsh, plugins, nvm, uv, .zshrc
# ---------------------------------------------------------------------------
install_oh_my_zsh() {
  [ -d "$HOME/.oh-my-zsh" ] && return $SKIP
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
}

install_zsh_syntax_highlighting() {
  [ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && return $SKIP
  brew_formula zsh-syntax-highlighting
}

install_nvm() {
  [ -s "$HOME/.nvm/nvm.sh" ] && return $SKIP
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | PROFILE=/dev/null bash
}

install_node_npm() {
  local nvm_sh="$HOME/.nvm/nvm.sh"
  [ -s "$nvm_sh" ] || { echo "nvm is not installed." >&2; return 1; }
  . "$nvm_sh" || return 1
  if nvm use default >/dev/null 2>&1 && have_cmd node && have_cmd npm; then
    return $SKIP
  fi
  nvm install --lts || return 1
  nvm alias default 'lts/*' || return 1
  nvm use default >/dev/null || return 1
  have_cmd node && have_cmd npm
}

install_uv() {
  { have_cmd uv || [ -x "$HOME/.local/bin/uv" ]; } && return $SKIP
  curl -LsSf https://astral.sh/uv/install.sh | env INSTALLER_NO_MODIFY_PATH=1 sh
}

install_claude_code() {
  { have_cmd claude || [ -x "$HOME/.local/bin/claude" ]; } && return $SKIP
  curl -fsSL https://claude.ai/install.sh | bash
}

config_zshrc() {
  [ -f "$HOME/.zshrc" ] && cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$TS"
  cat > "$HOME/.zshrc" <<'EOF'
# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(git)

[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"

# User configuration
export PATH="/opt/homebrew/bin:$PATH"

[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && \
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
export PATH="$HOME/.local/bin:$PATH"

# Added by Antigravity
export PATH="$HOME/.antigravity/antigravity/bin:$PATH"
EOF
}

# ---------------------------------------------------------------------------
# 8. DMG / ZIP apps -> ~/Yashu/additionals/<folder>
# ---------------------------------------------------------------------------
install_app() {
  local folder app="$2" file="$3" url="$4"
  folder="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  local dir="$ADDITIONALS_DIR/$folder"
  have_app "$app" && return $SKIP
  mkdir -p "$dir" || return 1
  curl -fL -o "$dir/$file" "$url" || return 1

  case "$file" in
    *.dmg)
      local mnt
      mnt="$(mktemp -d /tmp/dmg.XXXXXX)"
      hdiutil attach -nobrowse -quiet -mountpoint "$mnt" "$dir/$file" || return 1
      ditto "$mnt/$app.app" "/Applications/$app.app"
      local rc=$?
      hdiutil detach -quiet "$mnt"
      return $rc
      ;;
    *.zip)
      local tmp
      tmp="$(mktemp -d /tmp/zip.XXXXXX)"
      ditto -xk "$dir/$file" "$tmp" && ditto "$tmp/$app.app" "/Applications/$app.app"
      local rc=$?
      rm -rf "$tmp"
      return $rc
      ;;
  esac
}

install_chrome() { install_app chrome "Google Chrome" googlechrome.dmg "https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg"; }
install_brave()  { install_app brave "Brave Browser" Brave-Browser.dmg "https://laptop-updates.brave.com/latest/osx"; }
install_vscode() { install_app vsc "Visual Studio Code" VSCode.zip "https://update.code.visualstudio.com/latest/darwin-universal/stable"; }
install_postman() { brew_cask postman Postman; }
cleanup_brew_cache() {
  load_brew
  have_cmd brew || return $SKIP
  brew cleanup --prune=all --scrub
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
step "Xcode Command Line Tools"      install_clt
step "Homebrew"                      install_homebrew
step "Git"                           install_git
step "Git aliases & push config"     config_git
step "Docker Desktop"                install_docker
step "Docker images (mysql:8.0, postgres:16, redis, mongo)" pull_docker_images
step "Ollama"                        install_ollama
step "SSH config"                    config_ssh
step "cloudflared"                   install_cloudflared
step "AWS CLI"                       install_awscli
step "Python"                        install_python
step "Oh My Zsh"                     install_oh_my_zsh
step "zsh-syntax-highlighting"       install_zsh_syntax_highlighting
step "nvm"                           install_nvm
step "Node.js (npm)"                install_node_npm
step "uv"                            install_uv
step "Claude Code CLI"               install_claude_code
step ".zshrc"                        config_zshrc
step "Google Chrome"                 install_chrome
step "Brave Browser"                 install_brave
step "VS Code"                       install_vscode
step "Postman"                       install_postman
step "Homebrew cache cleanup"        cleanup_brew_cache

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n\033[1m================ SUMMARY ================\033[0m\n'
printf '\033[1;32mDone:\033[0m\n'
for s in "${DONE[@]}"; do echo "  [x] $s"; done
if [ ${#SKIPPED[@]} -gt 0 ]; then
  printf '\033[1;36mAlready installed (skipped):\033[0m\n'
  for s in "${SKIPPED[@]}"; do echo "  [-] $s"; done
fi
if [ ${#FAILED[@]} -gt 0 ]; then
  printf '\033[1;31mNot done:\033[0m\n'
  for s in "${FAILED[@]}"; do echo "  [ ] $s"; done
fi
echo
echo "Backups (if any): ~/.zshrc.bak.$TS, ~/.ssh/config.bak.$TS"
echo "Open a new terminal or run: source ~/.zshrc"
