#!/bin/zsh

echo "Starting Minecraft Server 2..."

# -------- CONFIG --------
SERVER_DIR="$HOME/Desktop/mc-server-2"
JAR_NAME="server.jar"
RAM="4G"

PLAYIT_BIN="$HOME/playit-agent/target/release/playit-cli"
# ------------------------

# Start Minecraft Server 2
cd "$SERVER_DIR" || exit 1
java -Xms$RAM -Xmx$RAM -jar "$JAR_NAME" nogui &

# Give server time to bind port
sleep 8

echo "Starting Playit agent..."
PLAYIT_FORCE_IPV4=1 "$PLAYIT_BIN"
