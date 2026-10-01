# World of Warcraft: Forever on Arch Linux

This runs Blizzard's Windows Battle.net app through Steam and Proton, then installs and tunes
**World of Warcraft: Forever** from it. Blizzard doesn't support Linux, so this is a
community setup, not an official one.

Status as of 2026-10-01:

- **Forever is a separate client.** In Battle.net it's a choice in the World of Warcraft
  version dropdown, the same one that switches to Classic.
- **Beta:** live since 17 Sept 2026. Only the **Skyborne Epic Pack** and the **Warcraft
  Forever Collection** pre-purchases include beta access; the Heroic Pack doesn't.
- **Launch:** 4 Nov 2026.
- **Requirements:** a DirectX 12 GPU with at least 4 GB of VRAM (GTX 10xx / RDNA 1 minimum,
  RTX 40xx / RDNA 3 recommended) and 128 GB free on an SSD.

## Quick start

```bash
cd setup/arch-wow-forever
./01-prepare-arch.sh --dry-run      # see what will change
./01-prepare-arch.sh                # packages, GPU driver bits, GameMode, NTSYNC
#   Steam: add Battle.net-Setup.exe as a non-Steam game, force Proton, run it (steps 2-3)
./02-battlenet-helper.sh find       # prints what to paste into the Steam shortcut
./02-battlenet-helper.sh link-games # keep the 128 GB install outside the prefix
#   Battle.net: World of Warcraft > version: Forever > Install
```

## Step 1: Prepare Arch

```bash
./01-prepare-arch.sh --dry-run   # optional preview
./01-prepare-arch.sh
```

The script is safe to re-run. It checks each item before changing anything and uses sudo only
where it has to:

| Item | What it does |
| --- | --- |
| multilib | Enables the multilib repository if it's off (backs up `/etc/pacman.conf` first). Steam and Proton need 32-bit libraries. |
| GPU driver | Detects your GPU and installs the 64-bit and 32-bit Vulkan driver: RADV (`vulkan-radeon`) for AMD, ANV (`vulkan-intel`) for Intel, `lib32-nvidia-utils` for NVIDIA. It warns about AMDVLK (discontinued), which can override RADV. |
| Packages | Installs `steam`, `gamemode`, `mangohud` (all with their `lib32-` versions), `vulkan-tools` and `ttf-liberation`. This runs as a full `pacman -Syu`, because partial upgrades break Arch. |
| GameMode | Adds you to the `gamemode` group so it can renice the game and switch the CPU governor. |
| NTSYNC | Loads the `ntsync` kernel module now and at every boot. Proton 11 and GE-Proton use it automatically, which smooths frame pacing in heavily threaded games like WoW. It needs kernel 6.14 or newer: `linux` and `linux-zen` qualify; older LTS kernels don't. |
| `vm.max_map_count` | Checks it's at least 1048576. Arch already defaults to that. |
| Storage | Creates `~/Games/Blizzard` and warns if it has less than 128 GB free or is on a spinning disk. Use `GAMES_DIR=/mnt/fast/Games ./01-prepare-arch.sh` to put it elsewhere. |

**NVIDIA:** the script won't install a kernel driver itself, because you choose that and need
to reboot after. If none is installed, it stops and prints the right command for your card:

- RTX 20xx / GTX 16xx or newer: `nvidia-open`, or `nvidia-open-dkms` on linux-zen and other
  non-stock kernels.
- GTX 10xx or older: `nvidia-580xx-dkms` from the AUR. The 590 driver dropped these cards.

Pascal cards (GTX 10xx) are Forever's bare minimum. There are also open reports of whole-system
GPU hangs at the Forever loading screen on them
([ValveSoftware/Proton#10157](https://github.com/ValveSoftware/Proton/issues/10157)).

**Laptops with two GPUs:** for NVIDIA plus Intel or AMD, the recommended launch options already
include the PRIME offload variables. For AMD plus AMD, put `DRI_PRIME=1` in front of the launch
options.

If the script added you to the `gamemode` group, log out and back in before continuing.

## Step 2: Download the Battle.net installer

Download it from <https://download.battle.net/en-us/?product=bnetdesk>. That gives you
`~/Downloads/Battle.net-Setup.exe`.

## Step 3: Add it to Steam and run it under Proton

1. In Steam, go to **Games → Add a Non-Steam Game to My Library… → Browse…**. Switch the file
   type filter to **All Files**, pick `Battle.net-Setup.exe`, then click **Add Selected Programs**.
2. Right-click the new entry and choose **Properties → Compatibility**. Tick **Force the use of
   a specific Steam Play compatibility tool** and choose **Proton Experimental**.
3. Press **Play**. Install to the default `C:\Program Files (x86)\Battle.net`.
4. When the Battle.net login window appears, close Battle.net completely: use **Stop** in Steam
   if it lingers.

Proton 9 and older trigger the "Agent went to sleep" error, so use Experimental, Proton 11 or a
current GE-Proton.

## Step 4: Point the shortcut at the installed launcher

```bash
./02-battlenet-helper.sh find
```

This finds the Proton prefix Steam just created and prints three values: **Target**,
**Start In** and **Launch Options**. Paste them into the shortcut's **Properties → Shortcut**
tab and rename the shortcut to `Battle.net`. The launch options look like this (AMD/Intel shown):

```
MESA_SHADER_CACHE_MAX_SIZE=10G gamemoderun %command%
```

- `gamemoderun` wraps Battle.net, so WoW inherits GameMode when Battle.net starts it.
- The shader-cache variable gives the GPU driver room to keep compiled shaders between sessions.
  Non-Steam games don't get Steam's shader pre-caching, and WoW compiles a lot of them. NVIDIA
  gets the equivalent `__GL_SHADER_DISK_CACHE_*` variables.
- Optional: add `mangohud` before `%command%` for an FPS and frame-time overlay. Right Shift+F12
  toggles it.

## Step 5: Keep the game outside the prefix (before installing WoW)

```bash
./02-battlenet-helper.sh link-games
```

This makes `C:\Program Files (x86)\World of Warcraft` inside the prefix a symlink to
`~/Games/Blizzard/World of Warcraft`. The most common Battle.net fix is to delete and recreate
the Proton prefix. With the game outside it, a reset no longer means another 128 GB download.

## Step 6: Install WoW: Forever

1. Launch **Battle.net** from Steam and sign in.
2. Open **World of Warcraft**. In the version dropdown above the Install/Play button, choose
   **World of Warcraft: Forever**, or the Forever beta entry while the beta runs.
3. Install to the default `C:\Program Files (x86)\World of Warcraft`. Because of step 5, the
   files actually land in `~/Games/Blizzard`.

If the Forever option doesn't appear right after purchase, quit and restart Battle.net. If it
still doesn't show, check that your pack includes beta access.

## Step 7: In-game settings that matter on Linux

These come from Linux players' reports in the Forever beta:

- **Graphics API:** the default is DX12, which runs through vkd3d-proton. If the game crashes or
  freezes at the end of the loading screen when you enter the world, try these in order:
  1. Set **Secondary Lighting** to **Fair**. It has been seen switching itself back to High, so
     re-check it.
  2. Switch the graphics API to **DX11**, which runs through DXVK. If you can't get far enough
     into the game to change it:
     ```bash
     ls ~/Games/Blizzard/"World of Warcraft"        # find the flavor folder, e.g. _forever_
     ./02-battlenet-helper.sh wow-api d3d11 _forever_
     ```
  3. Lower the overall graphics preset a notch.
- **Triple Buffering:** turn it off. It adds input lag and has been linked to freezes.
- **Max Foreground FPS:** set it to your monitor's refresh rate.
- **Max Background FPS:** set it to around 30. This cuts heat and CPU load while you're tabbed
  out.
- **Ray-traced shadows:** these may show as unsupported under Proton. That's a known beta
  detection bug, and you lose little by skipping them.

## Optional extras

- **Other Proton versions:** if the launcher misbehaves on Experimental, try Proton 11.0 or the
  latest GE-Proton. Install GE-Proton with ProtonPlus (`yay -S protonplus`, or from Flathub as
  `com.vysp3r.ProtonPlus`), restart Steam, and pick it under Compatibility. Moving a prefix to a
  newer Proton is fine; moving it back to an older one often isn't.
- **Native Wayland:** add `PROTON_ENABLE_WAYLAND=1` (and `PROTON_ENABLE_HDR=1` for HDR) before
  `%command%`. This is experimental and disables the Steam overlay.
- **Flatpak Steam:** run `flatpak override --user --filesystem=~/Games com.valvesoftware.Steam`
  so the sandbox can follow the `link-games` symlink. The helper finds Flatpak prefixes too.
- **Fallback:** if Steam won't cooperate, Lutris has a ready-made Battle.net installer.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Battle.net window is black or blank | In Battle.net **Settings → App**, toggle **Use browser hardware acceleration**. If you can't see the window to do that, switch the shortcut to another Proton version, change the setting, then switch back. |
| "Agent went to sleep", or stuck on Updating/Initializing | Stop Battle.net, run `./02-battlenet-helper.sh fix-agent`, then relaunch. Make sure you're on Proton 10 or newer. |
| WoW shows **Install** although it's already installed | Click **Locate the game** under the button and choose `C:\Program Files (x86)\World of Warcraft`. It verifies the files instead of downloading them again. |
| Crash or freeze entering the world | See step 7: Secondary Lighting → Fair, then DX11, then a lower preset. |
| Heavy hitching for the first few hours | Shader caches are still filling. Each zone gets smoother on later visits. Check that the game is on an SSD and that `/dev/ntsync` exists. |
| Random hangs on Proton 11 | Add `PROTON_NO_NTSYNC=1` to the launch options to rule NTSYNC out. |
| Whole system locks up at the loading screen on a GTX 10xx | This is the open Pascal issue [ValveSoftware/Proton#10157](https://github.com/ValveSoftware/Proton/issues/10157). There's no fix yet. |
| Floating tray icon | Turn off Battle.net's minimise-to-tray option in its settings. |
| Start completely fresh | Delete `steamapps/compatdata/<id>` (the id is in the `find` output). Point the shortcut's Target back at `Battle.net-Setup.exe` and redo steps 3–5. Then use **Locate the game**: your WoW files in `~/Games/Blizzard` are untouched. |

## Sources

- [Install Battle.net on CachyOS using Steam and Proton (kriegalex)](https://gist.github.com/kriegalex/4a74c19f8aefd7487ef87854306be93e)
- [GamingOnLinux: How to install Battle.net on Linux, SteamOS and Steam Deck](https://www.gamingonlinux.com/guides/view/how-to-install-battle-net-on-linux-steamos-and-steam-deck-for-world-of-warcraft-and-starcraft/)
- [Blizzard: The World of Warcraft: Forever beta is now live](https://news.blizzard.com/en-us/article/24304160/the-world-of-warcraft-forever-beta-now-live)
- [Icy Veins: WoW Forever beta access](https://www.icy-veins.com/wow-forever/wow-forever-beta)
- [WoW Forever system requirements](https://esports.gg/guides/world-of-warcraft/can-your-pc-or-mac-run-wow-forever-here-are-the-system-requirements/)
- [Blizzard forums: crashing under Linux at the end of the loading screen](https://eu.forums.blizzard.com/en/wow/t/crashing-under-linux-at-end-of-loading-screen/629339)
- [ValveSoftware/Proton#10157: World of Warcraft: Forever](https://github.com/ValveSoftware/Proton/issues/10157)
- [Arch Linux news: NVIDIA 590 driver drops Pascal support](https://archlinux.org/news/nvidia-590-driver-drops-pascal-support-main-packages-switch-to-open-kernel-modules/)
- [ArchWiki: GameMode](https://wiki.archlinux.org/title/Gamemode)
- [Arch forums: loading the ntsync module](https://bbs.archlinux.org/viewtopic.php?id=309389)
