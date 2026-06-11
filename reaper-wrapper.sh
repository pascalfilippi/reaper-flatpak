#!/bin/sh
# Reaper launch wrapper for the Flatpak.
# Sets up env for the yabridge extension when present, and seeds Reaper to use
# the JACK backend (which is PipeWire-JACK under the hood) on first run.

set -eu

export YABRIDGE_DEBUG_LEVEL="${YABRIDGE_DEBUG_LEVEL:-3}"
YABRIDGE_DIR=/app/extensions/Plugins/yabridge

# yabridge integration — harmless if the extension isn't installed
if [ -d "$YABRIDGE_DIR" ]; then
    export YABRIDGE_HOME="$YABRIDGE_DIR"

    # Resolve WINEPREFIX against the HOST home, not the sandboxed $XDG_DATA_HOME.
    # Manager (separate Flatpak) writes the prefix at
    # <host-home>/.local/share/yabridge/wineprefix; both apps must point at the
    # same path or yabridge bridges into an empty prefix and Wine errors with
    # "chdir to /home/.../.var/app/.../data/yabridge/wineprefix: No such file
    # or directory". The sandbox rewrites $HOME / $XDG_*_HOME to per-app
    # overlays under ~/.var/app/<app-id>/, while --filesystem=home exposes the
    # host path under its original name. Mirrors manager.sh's HOST_HOME logic.
    if [ -f /.flatpak-info ]; then
        HOST_HOME="${HOME%/.var/app/*}"
    else
        HOST_HOME="$HOME"
    fi
    export WINEPREFIX="${WINEPREFIX:-$HOST_HOME/.local/share/yabridge/wineprefix}"
    export WINELOADER="$YABRIDGE_DIR/bin/wine"
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=}"
    # Wine's FUTEX2-based fast sync. Substantially lower audio-thread latency
    # for bridged plugins than Wine's default server-side sync — the single
    # biggest perf knob for yabridge'd plugins (Amplitube et al). Stable-25.08
    # Wine has fsync; Linux >= 5.16 supplies the kernel side. Harmless if
    # either is missing — Wine logs and falls back silently.
    export WINEFSYNC="${WINEFSYNC:-1}"
    # PATH is already extended via finish-args --env, but be defensive.
    case ":$PATH:" in
        *":$YABRIDGE_DIR/bin:"*) ;;
        *) export PATH="$YABRIDGE_DIR/bin:$PATH" ;;
    esac
fi

# First-run: nudge Reaper toward the JACK backend (PipeWire-JACK) instead of
# PulseAudio so we get native PipeWire latency. Only seeds if reaper.ini
# doesn't already exist — we never override a user's chosen backend.
REAPER_INI="$HOME/.config/REAPER/reaper.ini"
if [ ! -f "$REAPER_INI" ]; then
    mkdir -p "$(dirname "$REAPER_INI")"
    cat >"$REAPER_INI" <<'EOF'
[REAPER]
audioconfig=jack
EOF
fi

# Sensible default PipeWire quantum for low latency; user can override.
export PIPEWIRE_LATENCY="${PIPEWIRE_LATENCY:-256/48000}"

exec /app/extra/REAPER/reaper "$@"
