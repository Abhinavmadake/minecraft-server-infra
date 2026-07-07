#!/bin/zsh
# create-server.sh — scaffold a new Purpur server and register it with the
# launcher: downloads the latest Purpur jar, accepts the EULA (with your
# consent), writes a tuned server.properties, and creates servers/<name>.env.
#
# Usage: ./create-server.sh <name> [--version <mc-version>] [--port <port>]
#                                  [--ram <heap>] [--yes-eula]
#
# Servers are created under $SERVERS_ROOT (default: ~/minecraft-servers).

set -eu

SCRIPT_DIR="${0:A:h}"
SERVERS_ROOT="${SERVERS_ROOT:-$HOME/minecraft-servers}"
PURPUR_API="https://api.purpurmc.org/v2/purpur"

NAME=""
VERSION=""
PORT="25565"
RAM="2G"
YES_EULA=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)  VERSION="$2"; shift 2 ;;
    --port)     PORT="$2"; shift 2 ;;
    --ram)      RAM="$2"; shift 2 ;;
    --yes-eula) YES_EULA=1; shift ;;
    -*)         echo "Unknown option: $1"; exit 1 ;;
    *)          NAME="$1"; shift ;;
  esac
done

if [[ -z "$NAME" ]]; then
  echo "Usage: $0 <name> [--version <mc-version>] [--port <port>] [--ram <heap>] [--yes-eula]"
  exit 1
fi

SERVER_DIR="$SERVERS_ROOT/$NAME"
ENV_FILE="$SCRIPT_DIR/servers/$NAME.env"

if [[ -e "$SERVER_DIR" || -e "$ENV_FILE" ]]; then
  echo "Server '$NAME' already exists ($SERVER_DIR or $ENV_FILE). Pick another name."
  exit 1
fi

# Running a server requires agreeing to the Minecraft EULA; never do it silently.
if [[ $YES_EULA -ne 1 ]]; then
  read "REPLY?Do you agree to the Minecraft EULA (https://aka.ms/MinecraftEULA)? [y/N] "
  if [[ "$REPLY" != [yY] ]]; then
    echo "EULA not accepted; aborting."
    exit 1
  fi
fi

if [[ -z "$VERSION" ]]; then
  echo "==> Fetching latest Purpur version"
  VERSION="$(curl -fsS "$PURPUR_API" \
    | sed -E 's/.*"versions":[[]([^]]*)[]].*/\1/' \
    | tr -d '"' | tr ',' '\n' | tail -1)"
  if [[ -z "$VERSION" ]]; then
    echo "Could not determine latest version from $PURPUR_API"
    exit 1
  fi
fi
echo "==> Creating '$NAME' (Purpur $VERSION, port $PORT, heap $RAM)"

mkdir -p "$SERVER_DIR"

echo "==> Downloading Purpur $VERSION"
curl -fL --progress-bar -o "$SERVER_DIR/server.jar" \
  "$PURPUR_API/$VERSION/latest/download"

echo "eula=true" > "$SERVER_DIR/eula.txt"

# High view distance / low simulation distance: players see far, but
# entity and redstone ticking (the CPU cost) stays cheap.
cat > "$SERVER_DIR/server.properties" <<EOF
server-port=$PORT
motd=$NAME
view-distance=24
simulation-distance=5
EOF

mkdir -p "$SCRIPT_DIR/servers"
cat > "$ENV_FILE" <<EOF
# Created by create-server.sh on $(date +%Y-%m-%d) — Purpur $VERSION
SESSION=$NAME
SERVER_DIR=$SERVER_DIR
SERVER_JAR=server.jar
RAM=$RAM
JAVA_VERSION=latest
EOF

echo ""
echo "==> Done. Start it with:  ./start-server.sh $NAME"
