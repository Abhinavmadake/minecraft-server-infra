#!/bin/zsh
# start-server.sh — launch a Minecraft server and a playit.gg tunnel side by
# side in a tmux session, so both survive the terminal closing.
#
# Usage: ./start-server.sh <name>
#   Reads servers/<name>.env for SESSION, SERVER_DIR, SERVER_JAR, RAM.

set -eu

SCRIPT_DIR="${0:A:h}"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <server-name>"
  echo "Available servers:"
  ls "$SCRIPT_DIR/servers" | sed -e 's/\.env$//' -e 's/^/  - /'
  exit 1
fi

CONFIG="$SCRIPT_DIR/servers/$1.env"
if [[ ! -f "$CONFIG" ]]; then
  echo "No config found at $CONFIG"
  exit 1
fi
source "$CONFIG"

PURPUR_API="https://api.purpurmc.org/v2/purpur"

# --- update check ----------------------------------------------------------
# On interactive starts, compare the installed version (version_history.json,
# written by the server) against the Purpur API and offer to update. Never
# blocks startup: offline, non-Purpur, or non-interactive runs skip silently.
# Opt out with SKIP_UPDATE_CHECK=1.

update_jar() {  # $1 = version to install
  local ver="$1" tmp="$SERVER_DIR/$SERVER_JAR.new"
  echo "Downloading Purpur $ver..."
  if curl -fL --progress-bar -o "$tmp" "$PURPUR_API/$ver/latest/download"; then
    cp "$SERVER_DIR/$SERVER_JAR" "$SERVER_DIR/$SERVER_JAR.bak"
    mv "$tmp" "$SERVER_DIR/$SERVER_JAR"
    echo "Updated. Previous jar kept as $SERVER_JAR.bak"
    # MC 26.1+ requires Java 25+; bump this server's pinned JDK to match.
    if [[ "${ver%%.*}" -ge 26 && "${JAVA_VERSION:-21}" != "latest" ]]; then
      if grep -q '^JAVA_VERSION=' "$CONFIG"; then
        sed -i '' 's/^JAVA_VERSION=.*/JAVA_VERSION=latest/' "$CONFIG"
      else
        echo "JAVA_VERSION=latest" >> "$CONFIG"
      fi
      JAVA_VERSION=latest
      echo "Note: MC $ver needs Java 25+ — set JAVA_VERSION=latest in ${CONFIG:t}"
    fi
  else
    rm -f "$tmp"
    echo "Download failed; keeping the current jar."
  fi
}

check_updates() {
  if [[ ! -t 0 && -z "${FORCE_UPDATE_CHECK:-}" ]]; then return 0; fi
  if [[ "${SKIP_UPDATE_CHECK:-0}" == "1" ]]; then return 0; fi
  # Pointless (and unsafe) to swap the jar under a running server.
  if TMUX_TMPDIR="$HOME/.tmux-tmp" tmux has-session -t "$SESSION" 2>/dev/null; then return 0; fi
  local hist="$SERVER_DIR/version_history.json"
  if [[ ! -f "$hist" ]]; then return 0; fi

  # currentVersion looks like "1.21.11-2545-9f8e602 (MC: 1.21.11)"
  local current cur_ver cur_build
  current="$(sed -E 's/.*"currentVersion":"([^"]+)".*/\1/' "$hist")"
  cur_ver="${current%%-*}"
  cur_build="$(print -r -- "$current" | cut -d- -f2)"

  local latest_ver
  latest_ver="$(curl -fsS -m 5 "$PURPUR_API" 2>/dev/null \
    | sed -E 's/.*"versions":[[]([^]]*)[]].*/\1/' | tr -d '"' | tr ',' '\n' | tail -1)"
  if [[ -z "$latest_ver" ]]; then return 0; fi

  if [[ "$latest_ver" != "$cur_ver" ]]; then
    read "REPLY?Minecraft $latest_ver is out (installed: $cur_ver). Upgrade now? [y/N] "
    if [[ "$REPLY" == [yY] ]]; then update_jar "$latest_ver"; fi
    return 0
  fi

  local latest_build
  latest_build="$(curl -fsS -m 5 "$PURPUR_API/$cur_ver" 2>/dev/null \
    | sed -E 's/.*"latest": ?"([^"]+)".*/\1/')"
  if [[ -n "$latest_build" && -n "$cur_build" && "$latest_build" != "$cur_build" ]]; then
    read "REPLY?New Purpur build $latest_build for MC $cur_ver is out (installed: $cur_build). Update now? [y/N] "
    if [[ "$REPLY" == [yY] ]]; then update_jar "$cur_ver"; fi
  else
    echo "Purpur $cur_ver build $cur_build — up to date."
  fi
}

check_updates

# --- java ------------------------------------------------------------------
# Resolve the JDK per server — MC 1.20.5–1.21.x needs Java 21, MC 26.1+
# needs Java 25+. JAVA_VERSION comes from the server's .env ("latest" = the
# newest installed JDK). Checks java_home first, then Homebrew kegs (which
# aren't registered with java_home unless symlinked).
JAVA_VERSION="${JAVA_VERSION:-21}"
resolve_java() {
  local v="$1" p
  if [[ "$v" == "latest" ]]; then
    for p in /opt/homebrew/opt/openjdk/bin/java "$(/usr/libexec/java_home 2>/dev/null)/bin/java"; do
      [[ -x "$p" ]] && { echo "$p"; return 0 }
    done
  else
    local jh
    if jh="$(/usr/libexec/java_home -v "$v" 2>/dev/null)"; then
      echo "$jh/bin/java"; return 0
    fi
    p="/opt/homebrew/opt/openjdk@$v/bin/java"
    [[ -x "$p" ]] && { echo "$p"; return 0 }
  fi
  return 1
}
if ! JAVA="$(resolve_java "$JAVA_VERSION")"; then
  echo "No Java $JAVA_VERSION found. Run ./setup.sh to install JDKs."
  exit 1
fi

# playit.gg ships no macOS ARM binary, so the agent is built from source:
#   git clone https://github.com/playit-cloud/playit-agent ~/playit-agent
#   cd ~/playit-agent && cargo build --release
PLAYIT="${PLAYIT:-$HOME/playit-agent/target/release/playit-cli}"

# tmux on macOS can fail to create its socket under the default /private/tmp
# path when permissions drift; keep the runtime dir somewhere we own.
export TMUX_TMPDIR="$HOME/.tmux-tmp"
mkdir -p "$TMUX_TMPDIR"
chmod 700 "$TMUX_TMPDIR"

tmux start-server 2>/dev/null || true

# Only attach when run from a real terminal (not from automation/CI).
attach() {
  if [[ -t 0 ]]; then
    exec tmux attach -t "$SESSION"
  else
    echo "(no TTY — session '$SESSION' left running detached)"
    exit 0
  fi
}

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' already running. Attaching..."
  attach
fi

echo "Starting tmux session: $SESSION"

# Left pane: the server. Fixed heap (Xms = Xmx) avoids heap-resize stalls;
# G1GC with a 200 ms pause target keeps tick times stable under load.
tmux new-session -d -s "$SESSION" \
  "cd '$SERVER_DIR' || exec zsh; \
   $JAVA -Xms$RAM -Xmx$RAM \
   -XX:+UseG1GC \
   -XX:MaxGCPauseMillis=200 \
   -jar $SERVER_JAR nogui; \
   exec zsh"

# Right pane: the tunnel agent (optional — LAN-only works without it).
if [[ -x "$PLAYIT" ]]; then
  tmux split-window -h -t "$SESSION" "$PLAYIT || exec zsh"
  tmux select-layout -t "$SESSION" even-horizontal
else
  echo "warning: playit-cli not found at $PLAYIT — starting without a tunnel."
  echo "         Run ./setup.sh to build it; the server is LAN-only until then."
fi

attach
