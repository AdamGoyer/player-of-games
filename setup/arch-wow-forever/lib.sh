# shellcheck shell=bash
# Shared helpers for the Arch + Steam/Proton + Battle.net + WoW: Forever scripts.
# Sourced, not executed.

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32mok\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m!!\033[0m  %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

confirm() { # confirm "question" -> success only on y/Y
  local reply
  read -r -p "$1 [y/N] " reply
  [[ $reply == [yY]* ]]
}

# Scan PCI display controllers (works whether or not a driver is loaded).
# Sets HAS_NVIDIA / HAS_AMD / HAS_INTEL to 0|1 and NVIDIA_DEVICE_IDS to the
# NVIDIA device ids found (e.g. 0x2684).
detect_gpus() {
  HAS_NVIDIA=0 HAS_AMD=0 HAS_INTEL=0
  NVIDIA_DEVICE_IDS=()
  local dev
  for dev in /sys/bus/pci/devices/*; do
    [[ -r $dev/class && $(<"$dev/class") == 0x03* ]] || continue
    case $(<"$dev/vendor") in
      0x10de) HAS_NVIDIA=1; NVIDIA_DEVICE_IDS+=("$(<"$dev/device")") ;;
      0x1002) HAS_AMD=1 ;;
      0x8086) HAS_INTEL=1 ;;
    esac
  done
}

# NVIDIA ids below 0x1e00 are Pascal (GTX 10xx) or older. The 590+ driver
# dropped them, and WoW: Forever lists GTX 10xx as its absolute minimum.
nvidia_is_pre_turing() { # nvidia_is_pre_turing 0x1b80
  (( 16#${1#0x} < 16#1e00 ))
}

kernel_at_least() { # kernel_at_least 6 14
  local release major minor
  release=$(uname -r)
  major=${release%%.*}
  minor=${release#*.}; minor=${minor%%[!0-9]*}
  (( major > $1 || (major == $1 && minor >= $2) ))
}

# Steam launch options tuned for the GPU vendor. gamemoderun wraps the whole
# Battle.net process tree, so WoW inherits it when Battle.net starts the game.
recommended_launch_options() {
  detect_gpus
  if (( HAS_NVIDIA && !HAS_AMD && !HAS_INTEL )); then
    echo '__GL_SHADER_DISK_CACHE_SIZE=10737418240 __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1 gamemoderun %command%'
  elif (( HAS_NVIDIA )); then
    # Hybrid laptop: render on the NVIDIA dGPU. These are the variables
    # prime-run (nvidia-prime) sets, spelled out so it needn't be installed.
    echo '__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia __GL_SHADER_DISK_CACHE_SIZE=10737418240 __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1 gamemoderun %command%'
  else
    echo 'MESA_SHADER_CACHE_MAX_SIZE=10G gamemoderun %command%'
  fi
}
