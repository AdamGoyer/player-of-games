#!/usr/bin/env bash
# Helpers for the Battle.net shortcut you added to Steam (see README.md).
#
# Usage: ./02-battlenet-helper.sh <command>
#   find            locate the Battle.net Proton prefix and print the Steam
#                   shortcut Target / Start In / Launch Options to paste in
#   link-games      keep the WoW install outside the prefix (run BEFORE
#                   installing WoW) so a prefix reset never costs a download
#   fix-agent       clear the Battle.net agent cache (fixes "agent went to
#                   sleep", stuck "Updating", endless spinners)
#   wow-api <d3d11|d3d12> [flavor]
#                   switch WoW's graphics API in Config.wtf, e.g. when it
#                   crashes before you can reach the in-game settings
#   launch-options  print the recommended Steam launch options
#
# Environment:
#   BNET_PREFIX=/path/to/compatdata/<id>/pfx   skip auto-detection
#   GAMES_DIR=/path                            default ~/Games/Blizzard

set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"

GAMES_DIR=${GAMES_DIR:-$HOME/Games/Blizzard}
BNET_REL="drive_c/Program Files (x86)/Battle.net"
WOW_REL="drive_c/Program Files (x86)/World of Warcraft"

# Every Steam library on the machine: native and Flatpak roots, plus any
# extra library folders listed in libraryfolders.vdf.
steam_libraries() {
  local root
  for root in "$HOME/.local/share/Steam" "$HOME/.steam/steam" \
              "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    [[ -d $root/steamapps ]] || continue
    echo "$root"
    sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' \
      "$root/steamapps/libraryfolders.vdf" 2>/dev/null || true
  done | while read -r lib; do
    if [[ -d $lib/steamapps ]]; then readlink -f "$lib"; fi
  done | sort -u
}

# Prefixes containing an installed Battle.net, newest first.
battlenet_prefixes() {
  local lib pfx
  while read -r lib; do
    for pfx in "$lib"/steamapps/compatdata/*/pfx; do
      if [[ -f "$pfx/$BNET_REL/Battle.net Launcher.exe" ]]; then echo "$pfx"; fi
    done
  done < <(steam_libraries) | xargs -r -d '\n' ls -dt --
}

pick_prefix() {
  if [[ -n ${BNET_PREFIX:-} ]]; then
    [[ -f "$BNET_PREFIX/$BNET_REL/Battle.net Launcher.exe" ]] \
      || die "BNET_PREFIX=$BNET_PREFIX has no $BNET_REL/Battle.net Launcher.exe"
    echo "$BNET_PREFIX"
    return
  fi
  local found
  mapfile -t found < <(battlenet_prefixes)
  (( ${#found[@]} )) || die "No Steam Proton prefix with Battle.net installed yet.
  Add Battle.net-Setup.exe to Steam as a non-Steam game, force Proton under
  Properties > Compatibility, run it once to install, then re-run this. (README step 3)"
  if (( ${#found[@]} > 1 )); then
    warn "Battle.net is installed in ${#found[@]} prefixes; using the newest. Others:" >&2
    printf '        %s\n' "${found[@]:1}" >&2
    warn "Set BNET_PREFIX=... to pick another." >&2
  fi
  echo "${found[0]}"
}

# Wine names each process after its .exe, so match process names rather than
# full command lines (which would also catch editors, shells, grep...).
battlenet_running() {
  pgrep -i '^(battle\.net|agent\.exe|wow)' >/dev/null
}

cmd_find() {
  local pfx appid dir
  pfx=$(pick_prefix)
  appid=$(basename "$(dirname "$pfx")")
  dir="$pfx/$BNET_REL"
  say "Battle.net found in Steam shortcut prefix $appid"
  echo "  $pfx"
  cat <<EOF

In Steam: right-click the shortcut > Properties > Shortcut, then set
(keep the double quotes):

  Name            Battle.net
  Target          "$dir/Battle.net Launcher.exe"
  Start In        "$dir/"
  Launch Options  $(recommended_launch_options)

EOF
  if [[ -L $pfx/$WOW_REL ]]; then
    ok "WoW install folder already lives outside the prefix: $(readlink -f "$pfx/$WOW_REL")"
  elif [[ ! -e $pfx/$WOW_REL ]]; then
    warn "Before installing WoW, run: $0 link-games"
  fi
}

cmd_link_games() {
  local pfx inside outside
  pfx=$(pick_prefix)
  inside="$pfx/$WOW_REL"
  outside="$GAMES_DIR/World of Warcraft"
  if [[ -L $inside ]]; then
    ok "already linked: $inside -> $(readlink -f "$inside")"
    return
  fi
  if [[ -d $inside ]] && [[ -n $(ls -A "$inside") ]]; then
    die "WoW is already installed inside the prefix. To move it out, stop Battle.net in Steam, then:
  mkdir -p \"$GAMES_DIR\" && mv \"$inside\" \"$outside\" && $0 link-games"
  fi
  [[ -d $inside ]] && rmdir "$inside"
  mkdir -p "$outside"
  ln -s "$outside" "$inside"
  ok "C:\\Program Files (x86)\\World of Warcraft now points to $outside"
  echo "  Install WoW to the default C:\\Program Files (x86)\\World of Warcraft in Battle.net;"
  echo "  the files land in $outside."
}

cmd_fix_agent() {
  local pfx cache backup
  pfx=$(pick_prefix)
  cache="$pfx/drive_c/ProgramData/Battle.net"
  battlenet_running && die "Battle.net or WoW is still running. Stop it in Steam first."
  if [[ ! -d $cache ]]; then
    ok "no agent cache to clear"
    return
  fi
  backup="$cache.bak-$(date +%Y%m%d-%H%M%S)"
  confirm "Move the Battle.net agent cache aside to $(basename "$backup")? Your games and login are kept." \
    || { echo "Nothing changed."; return; }
  mv -- "$cache" "$backup"
  ok "Cleared. Launch Battle.net from Steam; it re-downloads its agent."
  echo "  If WoW then shows an Install button, click 'Locate the game' under it and pick"
  echo "  C:\\Program Files (x86)\\World of Warcraft: it verifies files instead of re-downloading."
  echo "  Once everything works you can delete $backup"
}

cmd_wow_api() {
  local api=${1:-} flavor=${2:-} gx pfx cfg changed=0
  case ${api,,} in
    d3d11|dx11) gx=D3D11 ;;
    d3d12|dx12) gx=D3D12 ;;
    *) die "usage: $0 wow-api <d3d11|d3d12> [flavor, e.g. _forever_]" ;;
  esac
  battlenet_running && die "Close WoW and Battle.net first; WoW rewrites Config.wtf on exit."
  pfx=$(pick_prefix)
  while IFS= read -r -d '' cfg; do
    [[ -z $flavor || $cfg == */"$flavor"/WTF/Config.wtf ]] || continue
    cp -- "$cfg" "$cfg.bak"
    if grep -q '^SET gxApi ' "$cfg"; then
      sed -i "s/^SET gxApi .*/SET gxApi \"$gx\"/" "$cfg"
    else
      printf 'SET gxApi "%s"\n' "$gx" >>"$cfg"
    fi
    ok "$gx -> $cfg"
    changed=1
  done < <(find -L "$pfx/$WOW_REL" -mindepth 3 -maxdepth 3 -path '*/WTF/Config.wtf' -print0 2>/dev/null)
  (( changed )) || die "No Config.wtf${flavor:+ for $flavor} found under $pfx/$WOW_REL.
  WoW writes it on first launch; start the game once, then re-run."
}

case ${1:-find} in
  find)           cmd_find ;;
  link-games)     cmd_link_games ;;
  fix-agent)      cmd_fix_agent ;;
  wow-api)        shift; cmd_wow_api "$@" ;;
  launch-options) recommended_launch_options ;;
  -h|--help|help) sed -n '2,/^$/s/^# \{0,1\}//p' "$0" ;;
  *) die "unknown command '$1' (try --help)" ;;
esac
