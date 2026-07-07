#!/bin/zsh

echo "Starting Minecraft Server 1 (Java + Bedrock)..."

# ---- CONFIG ----
SERVER_DIR="$HOME/Desktop/mc-server-1"
JAR_NAME="server.jar"
RAM="2G"
PLAYIT_BIN="$HOME/playit-agent/target/release/playit-cli"
# ----------------

# Start Minecraft server in background
cd "$SERVER_DIR" || exit 1
java -Xms$RAM -Xmx$RAM -jar "$JAR_NAME" nogui &

# Give the server time to bind ports
sleep 8

echo "Starting Playit agent..."
PLAYIT_FORCE_IPV4=1 "$PLAYIT_BIN"
