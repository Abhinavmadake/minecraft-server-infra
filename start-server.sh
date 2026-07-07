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
