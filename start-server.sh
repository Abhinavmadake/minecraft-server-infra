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

# Pin Java 21 explicitly — `java` on PATH may resolve to an older JDK.
JAVA21="$(/usr/libexec/java_home -v 21)/bin/java"

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

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' already running. Attaching..."
  exec tmux attach -t "$SESSION"
fi

echo "Starting tmux session: $SESSION"

# Left pane: the server. Fixed heap (Xms = Xmx) avoids heap-resize stalls;
# G1GC with a 200 ms pause target keeps tick times stable under load.
tmux new-session -d -s "$SESSION" \
  "cd '$SERVER_DIR' || exec zsh; \
   $JAVA21 -Xms$RAM -Xmx$RAM \
   -XX:+UseG1GC \
   -XX:MaxGCPauseMillis=200 \
   -jar $SERVER_JAR nogui; \
   exec zsh"

# Right pane: the tunnel agent.
tmux split-window -h -t "$SESSION" "$PLAYIT || exec zsh"

tmux select-layout -t "$SESSION" even-horizontal
exec tmux attach -t "$SESSION"
