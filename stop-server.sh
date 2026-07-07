#!/bin/zsh
# stop-server.sh — gracefully stop a running server: sends the `stop` command
# to its console (so the world saves), waits for shutdown, then closes the
# tmux session (which also stops the tunnel agent).
#
# Usage: ./stop-server.sh <name>

set -eu

SCRIPT_DIR="${0:A:h}"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <server-name>"
  exit 1
fi

CONFIG="$SCRIPT_DIR/servers/$1.env"
if [[ ! -f "$CONFIG" ]]; then
  echo "No config found at $CONFIG"
  exit 1
fi
source "$CONFIG"

export TMUX_TMPDIR="$HOME/.tmux-tmp"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "No running session '$SESSION'."
  exit 1
fi

# The JVM runs as a child of the pane's shell; track it by PID rather than
# tmux's #{pane_current_command}, which reports the shell, not java.
PANE_PID="$(tmux display-message -p -t "$SESSION:0.0" '#{pane_pid}')"

server_running() {
  pgrep -P "$PANE_PID" -x java >/dev/null 2>&1
}

if server_running; then
  echo "Sending 'stop' to $SESSION..."
  tmux send-keys -t "$SESSION:0.0" "stop" Enter

  for i in {1..60}; do
    server_running || break
    sleep 1
  done

  if server_running; then
    echo "Server did not stop within 60s; leaving session '$SESSION' running."
    exit 1
  fi
else
  echo "No server process found in session '$SESSION' (already stopped?)."
fi

tmux kill-session -t "$SESSION" 2>/dev/null || true
echo "Stopped '$1' and closed session '$SESSION'."
