#!/bin/sh
# Akahs for macOS and Linux: one command.
#
#   curl -fsSL https://downloads.akahs.com/cli.sh | sh                    # akahs-cli
#   curl -fsSL https://downloads.akahs.com/install.sh | sh                # the app
#   curl -fsSL https://downloads.akahs.com/install.sh | sh -s -- --both   # both
#
# akahs-cli: one file in ~/.local/bin (no sudo), checked against SHA256SUMS,
# added to PATH; `akahs-cli update` keeps it current. cli.sh is this script
# with --cli as the default.
# The app: macOS → the notarized Akahs.app in /Applications. Linux:
# Debian/Ubuntu/Mint/Pop!_OS/Kali → apt repo · Fedora → dnf repo (RHEL, Rocky
# and Alma have no WebKitGTK 4.1 → Flatpak) · openSUSE → zypper repo ·
# Arch/Manjaro → AUR (paru/yay) · anything else → Flatpak, else AppImage;
# those update with the system's own update command.
set -eu

BASE=${AKAHS_DL_BASE:-https://downloads.akahs.com}
MIRROR=${AKAHS_DL_MIRROR:-https://mirror.akahs.com}
PACKAGES=https://github.com/tharinchab/akahs-packages/releases/download
# Fixed release tags (never "latest": other Akahs apps publish there too).
CLI_RELEASES=${AKAHS_CLI_RELEASES:-$PACKAGES/cli}
APP_RELEASES=${AKAHS_APP_RELEASES:-$PACKAGES/v0.1.1}
MAC_RELEASES=${AKAHS_MAC_RELEASES:-$PACKAGES/macos}
CLI_DIR=${AKAHS_INSTALL_DIR:-$HOME/.local/bin}
FLATPAK_ID=com.akahs.Chat
WHAT=cli
DRY_RUN=${AKAHS_DRY_RUN:-0}

for arg in "$@"; do
  case $arg in
    --cli) WHAT=cli ;;
    --app) WHAT=app ;;
    --both) WHAT=both ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      echo "Usage: install.sh [--cli | --app | --both] [--dry-run]"
      echo "  --cli   akahs-cli into $CLI_DIR (AKAHS_INSTALL_DIR to change)"
      echo "  --app   the Akahs app (default)"
      echo "  --both  both"
      exit 0
      ;;
    *) echo "akahs: unknown option $arg (try --help)" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then B=$(printf '\033[1m'); G=$(printf '\033[32m'); D=$(printf '\033[2m'); R=$(printf '\033[0m'); else B= G= D= R=; fi
say() { printf '%s==>%s %s\n' "$B" "$R" "$*"; }
die() { printf 'akahs: %s\n' "$*" >&2; exit 1; }
run() {
  if [ "$DRY_RUN" = 1 ]; then echo "+ $*"; else "$@"; fi
}
have() { command -v "$1" >/dev/null 2>&1; }

SUDO=
need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    have sudo || die "run as root or install sudo"
    SUDO=sudo
  fi
}

fetch() { # <url> <out>
  if have curl; then curl -fsSL --retry 2 "$1" -o "$2"
  elif have wget; then wget -qO "$2" "$1"
  else die "install curl or wget"
  fi
}

sha256() {
  if have sha256sum; then sha256sum "$1" | cut -d' ' -f1
  elif have shasum; then shasum -a 256 "$1" | cut -d' ' -f1
  else die "need sha256sum or shasum to check the download"
  fi
}

# <dir with SHA256SUMS> <file> <name in the sums>
verify() {
  want=$(grep " \*\{0,1\}$3\$" "$1/SHA256SUMS" | cut -d' ' -f1 | head -1)
  [ -n "$want" ] || die "$3 isn't in SHA256SUMS"
  [ "$(sha256 "$2")" = "$want" ] || die "$3 doesn't match its checksum; nothing was installed. Try again."
}

OS=$(uname -s)
ARCH=$(uname -m)
case $ARCH in
  x86_64 | amd64) DEB_ARCH=amd64; APPIMAGE_ARCH=x86_64 ;;
  aarch64 | arm64) DEB_ARCH=arm64; APPIMAGE_ARCH=aarch64 ;;
  *) die "unsupported CPU: $ARCH (x86_64 and arm64 are supported)" ;;
esac

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t akahs)
trap 'rm -rf "$TMP"' EXIT INT TERM

# --- akahs-cli (every system) -----------------------------------------------------
PATH_HINT=
add_to_path() {
  case ":$PATH:" in *":$CLI_DIR:"*) return 0 ;; esac
  case $(basename "${SHELL:-sh}") in
    zsh) rc=${ZDOTDIR:-$HOME}/.zshrc; line="export PATH=\"$CLI_DIR:\$PATH\"" ;;
    bash)
      if [ "$OS" = Darwin ]; then rc=$HOME/.bash_profile; else rc=$HOME/.bashrc; fi
      line="export PATH=\"$CLI_DIR:\$PATH\"" ;;
    fish) rc=$HOME/.config/fish/conf.d/akahs.fish; line="fish_add_path -g $CLI_DIR" ;;
    *) rc=$HOME/.profile; line="export PATH=\"$CLI_DIR:\$PATH\"" ;;
  esac
  if [ "$DRY_RUN" = 1 ]; then echo "+ add $CLI_DIR to PATH in $rc"; return 0; fi
  if ! grep -qsF "$CLI_DIR" "$rc"; then
    mkdir -p "$(dirname "$rc")"
    printf '\n# akahs-cli\n%s\n' "$line" >> "$rc"
    say "Added $CLI_DIR to PATH in $rc"
  fi
  PATH_HINT="Open a new terminal, or run:  ${B}export PATH=\"$CLI_DIR:\$PATH\"${R}"
}

install_cli() {
  case $OS in
    Darwin) asset=akahs-cli-macos-universal.tar.gz ;;
    Linux)
      if ldd --version 2>&1 | grep -qi musl; then die "akahs-cli needs glibc; Alpine and other musl systems aren't supported yet"; fi
      asset=akahs-cli-$APPIMAGE_ARCH-linux.tar.gz ;;
    *) die "no akahs-cli for $OS. On Windows, in PowerShell: irm $BASE/cli.ps1 | iex" ;;
  esac
  say "Downloading akahs-cli"
  if [ "$DRY_RUN" = 1 ]; then
    echo "+ fetch $CLI_RELEASES/$asset (checked against SHA256SUMS) → $CLI_DIR/akahs-cli"
  else
    fetch "$CLI_RELEASES/SHA256SUMS" "$TMP/SHA256SUMS" || die "can't reach $CLI_RELEASES"
    fetch "$CLI_RELEASES/$asset" "$TMP/$asset" || die "can't download $asset"
    verify "$TMP" "$TMP/$asset" "$asset"
    mkdir -p "$TMP/cli" "$CLI_DIR"
    tar -xzf "$TMP/$asset" -C "$TMP/cli" akahs-cli
    chmod 755 "$TMP/cli/akahs-cli"
    # Same-folder rename: a running akahs-cli keeps working, the next start is new.
    cp "$TMP/cli/akahs-cli" "$CLI_DIR/.akahs-cli.new"
    mv -f "$CLI_DIR/.akahs-cli.new" "$CLI_DIR/akahs-cli"
    version=$("$CLI_DIR/akahs-cli" --version 2>/dev/null) || die "akahs-cli was installed but doesn't start on this system"
    say "${G}✓${R} Installed $version to $CLI_DIR/akahs-cli"
  fi
  add_to_path
}

# --- the app on macOS ------------------------------------------------------------
install_mac_app() {
  say "Downloading Akahs for Mac"
  if [ "$DRY_RUN" = 1 ]; then echo "+ fetch $MAC_RELEASES/Akahs-macos.dmg → /Applications/Akahs.app"; return 0; fi
  fetch "$MAC_RELEASES/SHA256SUMS" "$TMP/SHA256SUMS"
  fetch "$MAC_RELEASES/Akahs-macos.dmg" "$TMP/Akahs.dmg"
  verify "$TMP" "$TMP/Akahs.dmg" Akahs-macos.dmg
  mnt="$TMP/mnt"
  mkdir -p "$mnt"
  hdiutil attach -nobrowse -readonly -quiet -mountpoint "$mnt" "$TMP/Akahs.dmg"
  app=$(find "$mnt" -maxdepth 1 -name '*.app' | head -1)
  [ -n "$app" ] || { hdiutil detach -quiet "$mnt"; die "the disk image has no app"; }
  dest=/Applications
  [ -w "$dest" ] || { dest=$HOME/Applications; mkdir -p "$dest"; }
  rm -rf "$dest/$(basename "$app")"
  ditto "$app" "$dest/$(basename "$app")"
  hdiutil detach -quiet "$mnt" || true
  say "${G}✓${R} Installed $dest/$(basename "$app")"
}

# --- the app on Linux --------------------------------------------------------------
# Primary host, else the mirror (GitHub Pages can be blocked on some networks).
pick_base() {
  if fetch "$BASE/akahs.asc" "$TMP/akahs.asc" 2>/dev/null; then :
  elif fetch "$MIRROR/akahs.asc" "$TMP/akahs.asc" 2>/dev/null; then BASE=$MIRROR
  else die "can't reach $BASE or $MIRROR"
  fi
}

install_apt() {
  pick_base
  say "Adding the Akahs apt repository"
  run $SUDO mkdir -p /usr/share/keyrings
  fetch "$BASE/akahs.gpg" "$TMP/akahs.gpg"
  run $SUDO install -m 0644 "$TMP/akahs.gpg" /usr/share/keyrings/akahs.gpg
  line="deb [arch=$DEB_ARCH signed-by=/usr/share/keyrings/akahs.gpg] $BASE/apt stable main"
  if [ "$DRY_RUN" = 1 ]; then echo "+ echo '$line' > /etc/apt/sources.list.d/akahs.list"
  else echo "$line" | $SUDO tee /etc/apt/sources.list.d/akahs.list >/dev/null
  fi
  run $SUDO apt-get update -qq
  run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y akahs
}

# Native builds need glibc 2.35+ (built on Ubuntu 22.04).
glibc_ok() {
  v=$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$' || echo 0.0)
  major=${v%%.*} minor=${v#*.}
  [ "$major" -gt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -ge 35 ]; }
}

rpm_has_webkit41() { # <dnf|yum>
  "$1" -q provides 'libwebkit2gtk-4.1.so.0()(64bit)' >/dev/null 2>&1
}

apt_has_webkit41() {
  have apt-cache && apt-cache policy libwebkit2gtk-4.1-0 2>/dev/null | grep -q 'Candidate: [0-9]'
}

install_rpm_repo() { # <tool>
  pick_base
  say "Adding the Akahs rpm repository"
  fetch "$BASE/rpm/akahs.repo" "$TMP/akahs.repo"
  case $1 in
    zypper)
      run $SUDO rpm --import "$BASE/akahs.asc"
      run $SUDO install -m 0644 "$TMP/akahs.repo" /etc/zypp/repos.d/akahs.repo
      run $SUDO zypper --non-interactive --gpg-auto-import-keys refresh akahs
      run $SUDO zypper --non-interactive install akahs
      ;;
    *)
      run $SUDO install -m 0644 "$TMP/akahs.repo" /etc/yum.repos.d/akahs.repo
      run $SUDO rpm --import "$BASE/akahs.asc"
      run $SUDO "$1" install -y akahs
      ;;
  esac
}

install_aur() {
  helper=
  for h in paru yay; do have "$h" && helper=$h && break; done
  if [ -z "$helper" ]; then
    say "No AUR helper (paru or yay) found"
    return 1
  fi
  say "Installing akahs-bin from the AUR with $helper"
  # AUR helpers refuse to run as root; they call sudo themselves.
  run "$helper" -S --needed --noconfirm akahs-bin
}

install_flatpak() {
  have flatpak || return 1
  say "Installing Akahs from Flathub"
  run flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  run flatpak install --user -y flathub "$FLATPAK_ID"
}

install_appimage() {
  dest="$HOME/.local/bin"
  say "Installing the Akahs AppImage to $dest"
  run mkdir -p "$dest" "$HOME/.local/share/applications"
  run fetch "$APP_RELEASES/Akahs-$APPIMAGE_ARCH.AppImage" "$dest/Akahs.AppImage"
  run chmod +x "$dest/Akahs.AppImage"
  if [ "$DRY_RUN" != 1 ]; then
    cat > "$HOME/.local/share/applications/akahs.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Akahs
Comment=Akahs Chat
Exec=$dest/Akahs.AppImage %u
Icon=akahs
Terminal=false
Categories=Network;InstantMessaging;Chat;
MimeType=x-scheme-handler/akahs;
DESKTOP
    have update-desktop-database && update-desktop-database "$HOME/.local/share/applications" || true
  fi
  have fusermount || say "AppImages need FUSE 2: install libfuse2 (or fuse2) if Akahs doesn't start"
}

install_linux_app() {
  need_root
  [ -r /etc/os-release ] && . /etc/os-release
  ID=${ID:-unknown}
  family=" ${ID} ${ID_LIKE:-} "
  say "Detected ${PRETTY_NAME:-$ID} ($ARCH)"
  case $family in
    *" debian "* | *" ubuntu "*)
      run $SUDO apt-get update -qq
      if glibc_ok && apt_has_webkit41; then install_apt
      else say "This release has no WebKitGTK 4.1 (needs Ubuntu 22.04+ / Debian 12+)"; install_flatpak || install_appimage
      fi ;;
    *" fedora "* | *" rhel "* | *" centos "* | *" rocky "* | *" almalinux "*)
      tool=yum; have dnf && tool=dnf
      if glibc_ok && rpm_has_webkit41 "$tool"; then install_rpm_repo "$tool" || install_flatpak || install_appimage
      else say "This release has no WebKitGTK 4.1 (native packages need Fedora 37+; RHEL, Rocky and Alma use Flatpak)"; install_flatpak || install_appimage
      fi ;;
    *" opensuse "* | *" suse "* | *" sles "*)
      install_rpm_repo zypper || install_flatpak || install_appimage ;;
    *" arch "* | *" manjaro "* | *" endeavouros "*)
      install_aur || install_flatpak || install_appimage ;;
    *) say "No native package for $ID"; install_flatpak || install_appimage ;;
  esac
}

install_app() {
  case $OS in
    Darwin) install_mac_app ;;
    Linux) install_linux_app ;;
    *) die "on Windows, download Akahs from $BASE" ;;
  esac
}

# --- go ---------------------------------------------------------------------------------
case $WHAT in
  cli) install_cli ;;
  app) install_app ;;
  both) install_app; install_cli ;;
esac

echo
case $WHAT in
  app) say "Done. Open Akahs from your $( [ "$OS" = Darwin ] && echo Applications folder || echo app menu)." ;;
  *)
    if [ -n "$PATH_HINT" ]; then say "$PATH_HINT"; next=Then; else next=Now; fi
    say "$next run ${B}akahs-cli${R} to sign in and chat. ${D}Update any time: akahs-cli update${R}" ;;
esac
