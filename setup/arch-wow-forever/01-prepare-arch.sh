#!/usr/bin/env bash
# Step 1: prepare Arch Linux to run Battle.net + World of Warcraft: Forever
# through Steam and Proton. Safe to re-run: every step checks before it
# changes anything, and nothing is changed without sudo prompting you.
#
# Usage: ./01-prepare-arch.sh [--dry-run]
#   GAMES_DIR=/path  where the WoW install will live (default ~/Games/Blizzard)

set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"

DRY_RUN=0
case ${1:-} in
  --dry-run) DRY_RUN=1 ;;
  "") ;;
  *) die "unknown argument: $1 (only --dry-run is supported)" ;;
esac
GAMES_DIR=${GAMES_DIR:-$HOME/Games/Blizzard}
ME=$(id -un)
NEED_RELOGIN=0
BLOCKER=""

run() { if (( DRY_RUN )); then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }
write_root_file() { # write_root_file path line
  if (( DRY_RUN )); then printf '  [dry-run] write %s: %s\n' "$1" "$2"
  else printf '%s\n' "$2" | sudo tee "$1" >/dev/null; fi
}

(( EUID != 0 )) || die "Run this as your normal user; it calls sudo where it needs to."
command -v pacman >/dev/null || die "pacman not found. This script is for Arch Linux and Arch-based distros."
(( DRY_RUN )) && say "Dry run: showing what would change, changing nothing"

# --- 1. multilib (Steam and Proton need 32-bit libraries) -------------------
say "multilib repository"
if grep -qs '^\[multilib\]' /etc/pacman.conf; then
  ok "enabled"
else
  warn "disabled; enabling it (backup saved as /etc/pacman.conf.bak)"
  run sudo cp /etc/pacman.conf /etc/pacman.conf.bak
  run sudo sed -i '/^#\[multilib\]$/,/^#Include/ s/^#//' /etc/pacman.conf
  if (( !DRY_RUN )) && ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    die "Couldn't enable multilib automatically. Uncomment the [multilib] section in /etc/pacman.conf, then re-run."
  fi
fi

# --- 2. GPU drivers ---------------------------------------------------------
say "Graphics hardware"
detect_gpus
declare -A want=()
for p in steam gamemode lib32-gamemode mangohud lib32-mangohud vulkan-tools ttf-liberation; do
  want[$p]=1
done

if (( HAS_AMD )); then
  ok "AMD GPU found: using Mesa RADV (vulkan-radeon)"
  for p in mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon; do want[$p]=1; done
  if pacman -Qq amdvlk &>/dev/null || pacman -Qq lib32-amdvlk &>/dev/null; then
    warn "AMDVLK is installed. It is discontinued and can override RADV; remove it with: sudo pacman -Rns amdvlk lib32-amdvlk"
  fi
fi

if (( HAS_INTEL )); then
  ok "Intel GPU found: using Mesa ANV (vulkan-intel)"
  for p in mesa lib32-mesa vulkan-intel lib32-vulkan-intel; do want[$p]=1; done
fi

if (( HAS_NVIDIA )); then
  ok "NVIDIA GPU found (device ${NVIDIA_DEVICE_IDS[*]})"
  for id in "${NVIDIA_DEVICE_IDS[@]}"; do
    if nvidia_is_pre_turing "$id"; then
      warn "This NVIDIA card ($id) is Pascal (GTX 10xx) or older. WoW: Forever lists GTX 10xx as its"
      warn "minimum, current drivers no longer support it (AUR nvidia-580xx-dkms is the last), and there"
      warn "are open reports of GPU hangs on Pascal at the Forever loading screen (ValveSoftware/Proton#10157)."
    fi
  done
  if pacman -Qq nvidia-580xx-utils &>/dev/null; then
    ok "legacy 580xx driver installed"
    pacman -Qq lib32-nvidia-580xx-utils &>/dev/null \
      || BLOCKER="Install the 32-bit driver first: yay -S lib32-nvidia-580xx-utils"
  elif pacman -Qq nvidia-utils &>/dev/null; then
    ok "NVIDIA driver installed"
    want[nvidia-utils]=1 want[lib32-nvidia-utils]=1
  else
    warn "No NVIDIA driver is installed, and this script won't install a kernel driver for you."
    warn "  RTX 20xx / GTX 16xx or newer: sudo pacman -S nvidia-open nvidia-utils lib32-nvidia-utils"
    warn "    (use nvidia-open-dkms plus your kernel's -headers package if you run linux-zen etc.)"
    warn "  GTX 10xx or older: yay -S nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils"
    BLOCKER="Install the NVIDIA driver (above), reboot, then re-run this script."
  fi
fi

(( HAS_AMD || HAS_INTEL || HAS_NVIDIA )) || warn "No AMD/Intel/NVIDIA GPU detected. Install your Vulkan driver by hand."

# --- 3. packages ------------------------------------------------------------
say "Installing packages (pacman will list them and ask before changing anything)"
if [[ -n $BLOCKER ]]; then
  (( DRY_RUN )) || die "$BLOCKER"
  warn "$BLOCKER"
fi
mapfile -t pkgs < <(printf '%s\n' "${!want[@]}" | sort)
printf '  %s\n' "${pkgs[*]}"
# -Syu, not -Sy: partial upgrades are unsupported on Arch.
run sudo pacman -Syu --needed "${pkgs[@]}" || die "pacman didn't finish. Fix the error above and re-run."

# --- 4. GameMode ------------------------------------------------------------
say "GameMode"
if id -nG "$ME" | tr ' ' '\n' | grep -qx gamemode; then
  ok "$ME is in the gamemode group"
elif getent group gamemode >/dev/null || (( DRY_RUN )); then
  run sudo usermod -aG gamemode "$ME"
  NEED_RELOGIN=1
  ok "added $ME to the gamemode group (lets it renice the game and switch CPU governor)"
else
  warn "gamemode group missing; did the package install fail?"
fi

# --- 5. NTSYNC (Proton 11 / GE-Proton use it automatically when present) ----
say "NTSYNC kernel driver"
if kernel_at_least 6 14 && { [[ -e /dev/ntsync ]] || modinfo ntsync &>/dev/null; }; then
  if grep -qs '^ntsync$' "/lib/modules/$(uname -r)/modules.builtin" \
     || grep -rqsx 'ntsync' /etc/modules-load.d /usr/lib/modules-load.d; then
    ok "loads at boot"
  else
    write_root_file /etc/modules-load.d/ntsync.conf ntsync
    ok "set to load at boot (/etc/modules-load.d/ntsync.conf)"
  fi
  if [[ -e /dev/ntsync ]]; then
    ok "/dev/ntsync present"
  elif run sudo modprobe ntsync; then
    ok "loaded now"
  else
    warn "modprobe ntsync failed; Proton will fall back to fsync/esync (works, slightly less smooth)"
  fi
  if [[ -e /dev/ntsync && ! ( -r /dev/ntsync && -w /dev/ntsync ) ]]; then
    warn "/dev/ntsync isn't readable/writable by $ME, so Proton can't use it. Fix with:"
    warn "  echo 'KERNEL==\"ntsync\", MODE=\"0666\"' | sudo tee /etc/udev/rules.d/99-ntsync.rules && sudo udevadm trigger"
  fi
else
  warn "Kernel $(uname -r) has no NTSYNC driver (needs 6.14+ built with it; LTS kernels lag behind)."
  warn "Proton still works. For the smoothest frame pacing, boot the 'linux' or 'linux-zen' kernel."
fi

# --- 6. memory map limit (Arch already defaults to 1048576) -----------------
say "vm.max_map_count"
current=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
if (( current >= 1048576 )); then
  ok "$current"
else
  write_root_file /etc/sysctl.d/80-gamecompatibility.conf 'vm.max_map_count = 1048576'
  run sudo sysctl -qw vm.max_map_count=1048576
  ok "raised from $current to 1048576"
fi

# --- 7. game storage --------------------------------------------------------
say "Game storage: $GAMES_DIR"
run mkdir -p "$GAMES_DIR"
probe=$GAMES_DIR
while [[ ! -d $probe ]]; do probe=$(dirname "$probe"); done
avail_gb=$(df -BG --output=avail "$probe" | tail -n1 | tr -dc '0-9')
if (( avail_gb >= 128 )); then
  ok "${avail_gb} GB free (Forever asks for 128 GB)"
else
  warn "only ${avail_gb} GB free; Forever asks for 128 GB. Set GAMES_DIR to a bigger drive and re-run."
fi
source_dev=$(findmnt -no SOURCE -T "$probe" 2>/dev/null | sed 's/\[.*//') || true
if [[ -n $source_dev ]] && lsblk -sno ROTA "$source_dev" 2>/dev/null | grep -q 1; then
  warn "$probe is on a spinning disk. Forever requires an SSD; expect very long loading screens."
fi

# --- done -------------------------------------------------------------------
say "System prep finished"
(( NEED_RELOGIN )) && warn "Log out and back in (or reboot) so the gamemode group applies."
cat <<EOF

Next: follow README.md from "Step 2". The short version:
  1. Download Battle.net-Setup.exe from https://download.battle.net/en-us/?product=bnetdesk
  2. Steam > Add a Game > Add a Non-Steam Game > (show All Files) > Battle.net-Setup.exe
  3. Properties > Compatibility > force Proton Experimental, then run it to install
  4. ./02-battlenet-helper.sh find   (prints what to paste into the Steam shortcut)

Launch options to use for this machine:
  $(recommended_launch_options)
EOF
