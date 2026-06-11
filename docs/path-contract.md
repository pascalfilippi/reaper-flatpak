# Path / permission contract

Formal interface between the three components. Anyone editing one manifest
must check the others.

## Filesystem assets

| Asset | Path | Owner | DAW sees                         | Manager sees |
| --- | --- | --- |----------------------------------| --- |
| Wine binaries | `/app/extensions/Plugins/yabridge/bin/` | yabridge ext (RO) | RO via extension mount           | RO via extension mount |
| yabridge libs | `/app/extensions/Plugins/yabridge/lib/` | yabridge ext (RO) | RO via extension mount + LD path | RO via extension mount + LD path |
| Wine prefix | `~/.local/share/yabridge/wineprefix/` | Manager (RW) | RO via `--filesystem=home`       | RW via `--filesystem=xdg-data/yabridge:create` |
| VST3 stubs | `~/.vst3/yabridge/*.vst3` | Manager writes (RW) | RO via `--filesystem=home`       | RW via `--filesystem=home/.vst3:create` |
| VST2 stubs | `~/.vst/yabridge/*.so` | Manager writes (RW) | RO via `--filesystem=home`       | RW via `--filesystem=home/.vst:create` |
| CLAP stubs | `~/.clap/yabridge/*.clap` | Manager writes (RW) | RO via `--filesystem=home`       | RW via `--filesystem=home/.clap:create` |
| yabridgectl config | `~/.config/yabridge/` | Manager (RW) | RO via `--filesystem=home`       | RW via `--filesystem=home/.config/yabridge:create` |

The "DAW sees" column relies on DAW's flatpack havin `--filesystem=home`.

## Environment variables (set by both wrappers)

| Var | Value | Purpose |
| --- | --- | --- |
| `YABRIDGE_HOME` | `/app/extensions/Plugins/yabridge` | informational |
| `WINEPREFIX` | `${XDG_DATA_HOME:-$HOME/.local/share}/yabridge/wineprefix` | shared prefix location |
| `WINELOADER` | `/app/extensions/Plugins/yabridge/bin/wine` | force our Wine, not a stray host one |
| `WINEDLLOVERRIDES` | `winemenubuilder.exe=` | suppress `.desktop` pollution |
| `YABRIDGE_DEBUG_LEVEL` | `0` (default), `2` (debug) | yabridge log verbosity |
| `PATH` | `…:/app/extensions/Plugins/yabridge/bin` | so chainloader's `search_in_path` finds host binary |

## D-Bus

| Component | D-Bus permission | Why |
|-----------| --- | --- |
| DAW       | `--system-talk-name=org.freedesktop.RealtimeKit1` | acquire SCHED_FIFO via rtkit |
| DAW       | `--talk-name=org.freedesktop.portal.Desktop` | acquire RT via Realtime portal (PipeWire ≥ 0.3.50 path) |
| Manager   | (none beyond portal defaults) | uses xdg-desktop-portal for file chooser only |

## What MUST stay identical across manifests

The `add-extensions: org.freedesktop.LinuxAudio.Plugins:` block in DAW
and in the Manager. If they diverge:

- different `directory:` → extension mounts at different paths inside each
  sandbox → chainloader's resolved `/app/extensions/Plugins/yabridge/bin/wine`
  exists in one sandbox but not the other → bridging breaks.
- different `version:` → only one of DAW/Manager picks up the extension.
- different `add-ld-path:` → libs aren't on LD path in one sandbox.

Run `tools/verify-mount.sh` to confirm the mount points match in both running
sandboxes before claiming the system works.

## Wine prefix location decision

We use a *host-visible* path (`$XDG_DATA_HOME/yabridge/wineprefix/`), not the
Manager's per-app data dir (`~/.var/app/io.github.audioflatpak.YabridgeManager/`).

Reasoning: per-app data dirs aren't visible to other sandboxes by default.
The wineprefix must be readable by the DAW (so the Windows DLL paths in
`yabridge.toml` resolve when the chainloader's wine subprocess runs).
`--filesystem=home` covers `$XDG_DATA_HOME` because XDG
data is under `$HOME` for non-system users.

User-visible consequence: uninstalling the Manager Flatpak does **not** nuke
the user's installed Windows plugins. This must be documented in the Manager's
first-run dialog and README.
