#!/bin/zsh
# -------- JAVA --------
JAVA21="$(/usr/libexec/java_home -v 21)/bin/java"
# --- CRITICAL: tmux runtime fix ---
export TMUX_TMPDIR="$HOME/.tmux-tmp"
mkdir -p "$TMUX_TMPDIR"
chmod 700 "$TMUX_TMPDIR"
# ---------------------------------

SESSION="mc2"
SERVER_DIR="$HOME/Desktop/mc-server-2"
PLAYIT="$HOME/playit-agent/target/release/playit-cli"
RAM="4G"

# Ensure tmux server is running
tmux start-server 2>/dev/null

# Attach if session already exists
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session already running. Attaching..."
  tmux attach -t "$SESSION"
  exit 0
fi

echo "Starting new tmux session: $SESSION"

# Create tmux session with Minecraft
tmux new-session -d -s "$SESSION" \
  "cd '$SERVER_DIR' || exec zsh; \
   $JAVA21 -Xms$RAM -Xmx$RAM \
   -XX:+UseG1GC \
   -XX:MaxGCPauseMillis=200 \
   -jar server.jar nogui; \
   exec zsh"

# Split pane for Playit
tmux split-window -h -t "$SESSION" \
  "$PLAYIT || exec zsh"

tmux select-layout -t "$SESSION" even-horizontal
tmux attach -t "$SESSION"
