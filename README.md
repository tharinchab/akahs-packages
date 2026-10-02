# Akahs packages

Signed Linux repositories and release downloads for Akahs, served at
**https://downloads.akahs.com**. Published by the release workflow of the Akahs
desktop apps; don't edit by hand.

```sh
curl -fsSL https://downloads.akahs.com/install.sh | sh
```

| Distro | After install.sh, updates come from |
|---|---|
| Debian, Ubuntu, Mint, Pop!_OS, Kali | `sudo apt update && sudo apt upgrade` |
| Fedora, RHEL, Rocky, Alma | `sudo dnf upgrade` |
| openSUSE | `sudo zypper update` |
| Arch, Manjaro | your AUR helper (`akahs-bin`) |
| Anything else | Flathub (`com.akahs.Chat`) or the AppImage from Releases |
