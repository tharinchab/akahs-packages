#!/bin/sh
# Akahs for Linux: one command for every distro.
#
#   curl -fsSL https://downloads.akahs.com/install.sh | sh            # the app
#   curl -fsSL https://downloads.akahs.com/install.sh | sh -s -- --cli  # akahs-cli
#
# Debian/Ubuntu/Mint/Pop!_OS/Kali → apt repo · Fedora → dnf repo (RHEL,
# Rocky and Alma have no WebKitGTK 4.1 → Flatpak) · openSUSE → zypper repo · Arch/Manjaro → AUR (paru/yay) · anything
# else, or a distro too old for WebKitGTK 4.1 → Flatpak, else AppImage.
# After this, updates come with the system's normal update command.
set -eu

BASE=${AKAHS_DL_BASE:-https://downloads.akahs.com}
MIRROR=${AKAHS_DL_MIRROR:-https://mirror.akahs.com}
RELEASES=${AKAHS_RELEASES:-https://github.com/tharinchab/akahs-packages/releases/latest/download}
FLATPAK_ID=com.akahs.Chat
WHAT=app
DRY_RUN=${AKAHS_DRY_RUN:-0}

for arg in "$@"; do
  case $arg in
    --cli) WHAT=cli ;;
    --both) WHAT=both ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      sed -n '2,10p' "$0" 2>/dev/null || true
      exit 0
      ;;
    *) echo "akahs: unknown option $arg" >&2; exit 2 ;;
  esac
done

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf 'akahs: %s\n' "$*" >&2; exit 1; }
run() {
  if [ "$DRY_RUN" = 1 ]; then echo "+ $*"; else "$@"; fi
}
have() { command -v "$1" >/dev/null 2>&1; }

SUDO=
if [ "$(id -u)" -ne 0 ]; then
  have sudo || die "run as root or install sudo"
  SUDO=sudo
fi

fetch() { # <url> <out>
  if have curl; then curl -fsSL --retry 2 "$1" -o "$2"
  elif have wget; then wget -qO "$2" "$1"
  else die "install curl or wget"
  fi
}

# Primary host, else the mirror (GitHub Pages can be blocked on some networks).
pick_base() {
  tmp=$(mktemp)
  if fetch "$BASE/akahs.asc" "$tmp" 2>/dev/null; then :
  elif fetch "$MIRROR/akahs.asc" "$tmp" 2>/dev/null; then BASE=$MIRROR
  else rm -f "$tmp"; die "can't reach $BASE or $MIRROR"
  fi
  rm -f "$tmp"
}

ARCH=$(uname -m)
case $ARCH in
  x86_64 | amd64) DEB_ARCH=amd64; APPIMAGE_ARCH=x86_64 ;;
  aarch64 | arm64) DEB_ARCH=arm64; APPIMAGE_ARCH=aarch64 ;;
  *) die "unsupported CPU: $ARCH (x86_64 and aarch64 are supported)" ;;
esac

[ -r /etc/os-release ] && . /etc/os-release
ID=${ID:-unknown}
FAMILY=" ${ID} ${ID_LIKE:-} "

packages() {
  case $WHAT in
    app) echo akahs ;;
    cli) echo akahs-cli ;;
    both) echo "akahs akahs-cli" ;;
  esac
}

# --- apt ---------------------------------------------------------------------
install_apt() {
  pick_base
  say "Adding the Akahs apt repository"
  run $SUDO mkdir -p /usr/share/keyrings
  tmp=$(mktemp)
  fetch "$BASE/akahs.gpg" "$tmp"
  run $SUDO install -m 0644 "$tmp" /usr/share/keyrings/akahs.gpg
  rm -f "$tmp"
  line="deb [arch=$DEB_ARCH signed-by=/usr/share/keyrings/akahs.gpg] $BASE/apt stable main"
  if [ "$DRY_RUN" = 1 ]; then echo "+ echo '$line' > /etc/apt/sources.list.d/akahs.list"
  else echo "$line" | $SUDO tee /etc/apt/sources.list.d/akahs.list >/dev/null
  fi
  run $SUDO apt-get update -qq
  # shellcheck disable=SC2046
  run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y $(packages)
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

# --- dnf / yum / zypper ----------------------------------------------------------
install_rpm_repo() { # <tool>
  pick_base
  say "Adding the Akahs rpm repository"
  tmp=$(mktemp)
  fetch "$BASE/rpm/akahs.repo" "$tmp"
  case $1 in
    zypper)
      run $SUDO rpm --import "$BASE/akahs.asc"
      run $SUDO install -m 0644 "$tmp" /etc/zypp/repos.d/akahs.repo
      run $SUDO zypper --non-interactive --gpg-auto-import-keys refresh akahs
      # shellcheck disable=SC2046
      run $SUDO zypper --non-interactive install $(packages)
      ;;
    *)
      run $SUDO install -m 0644 "$tmp" /etc/yum.repos.d/akahs.repo
      run $SUDO rpm --import "$BASE/akahs.asc"
      # shellcheck disable=SC2046
      run $SUDO "$1" install -y $(packages)
      ;;
  esac
  rm -f "$tmp"
}

# --- Arch (AUR) ---------------------------------------------------------------------
install_aur() {
  helper=
  for h in paru yay; do have "$h" && helper=$h && break; done
  if [ -z "$helper" ]; then
    say "No AUR helper (paru or yay) found"
    return 1
  fi
  pkgs=
  for p in $(packages); do pkgs="$pkgs $p-bin"; done
  say "Installing$pkgs from the AUR with $helper"
  # AUR helpers refuse to run as root; they call sudo themselves.
  # shellcheck disable=SC2086
  run "$helper" -S --needed --noconfirm $pkgs
}

# --- universal fallbacks ------------------------------------------------------------
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
  run fetch "$RELEASES/Akahs-$APPIMAGE_ARCH.AppImage" "$dest/Akahs.AppImage"
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

install_cli_tarball() {
  dest="$HOME/.local/bin"
  say "Installing akahs-cli to $dest"
  run mkdir -p "$dest"
  tmp=$(mktemp)
  run fetch "$RELEASES/akahs-cli-$APPIMAGE_ARCH-linux.tar.gz" "$tmp"
  run tar -xzf "$tmp" -C "$dest" akahs-cli
  rm -f "$tmp"
}

fallback() {
  case $WHAT in
    cli) install_cli_tarball ;;
    *) install_flatpak || install_appimage
       [ "$WHAT" = both ] && install_cli_tarball ;;
  esac
}

# --- choose ---------------------------------------------------------------------------
say "Detected ${PRETTY_NAME:-$ID} ($ARCH)"
case $FAMILY in
  *" debian "* | *" ubuntu "*)
    [ "$WHAT" = cli ] || run $SUDO apt-get update -qq
    if [ "$WHAT" = cli ] || { glibc_ok && apt_has_webkit41; }; then install_apt
    else say "This release has no WebKitGTK 4.1 (needs Ubuntu 22.04+ / Debian 12+)"; fallback
    fi ;;
  *" fedora "* | *" rhel "* | *" centos "* | *" rocky "* | *" almalinux "*)
    tool=yum; have dnf && tool=dnf
    if [ "$WHAT" = cli ] || { glibc_ok && rpm_has_webkit41 "$tool"; }; then install_rpm_repo "$tool" || fallback
    else say "This release has no WebKitGTK 4.1 (native packages need Fedora 37+; RHEL, Rocky and Alma use Flatpak)"; fallback
    fi ;;
  *" opensuse "* | *" suse "* | *" sles "*)
    install_rpm_repo zypper || fallback ;;
  *" arch "* | *" manjaro "* | *" endeavouros "*)
    install_aur || fallback ;;
  *) say "No native package for $ID"; fallback ;;
esac

case $WHAT in
  cli) say "Done. Run: akahs-cli" ;;
  *) say "Done. Open Akahs from your app menu$( [ "$WHAT" = both ] && echo ', or run akahs-cli')." ;;
esac
