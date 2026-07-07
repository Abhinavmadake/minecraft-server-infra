#!/bin/zsh
# setup.sh — one-time setup: checks/installs dependencies and builds the
# playit.gg tunnel agent from source (no macOS ARM binary is published).
#
# Usage: ./setup.sh

set -eu

echo "==> Checking dependencies"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to install missing tools."
  echo "Install it from https://brew.sh and re-run this script."
  exit 1
fi

# Java 21 (MC 1.20.5–1.21.x) and latest JDK (MC 26.1+ needs Java 25+).
# Homebrew kegs aren't registered with java_home, so check both places.
if /usr/libexec/java_home -v 21 >/dev/null 2>&1 || [[ -x /opt/homebrew/opt/openjdk@21/bin/java ]]; then
  echo "  java 21    OK"
else
  echo "  java 21    missing — installing"
  brew install openjdk@21
fi

if [[ -x /opt/homebrew/opt/openjdk/bin/java ]]; then
  echo "  java       OK ($(/opt/homebrew/opt/openjdk/bin/java --version | head -1))"
else
  echo "  java       latest missing — installing"
  brew install openjdk
fi

if command -v tmux >/dev/null 2>&1; then
  echo "  tmux       OK"
else
  echo "  tmux       missing — installing"
  brew install tmux
fi

# Rust toolchain, needed only to build the tunnel agent below
if command -v cargo >/dev/null 2>&1; then
  echo "  cargo      OK"
else
  echo "  cargo      missing — installing Rust"
  brew install rust
fi

PLAYIT_DIR="${PLAYIT_DIR:-$HOME/playit-agent}"
PLAYIT="$PLAYIT_DIR/target/release/playit-cli"

if [[ -x "$PLAYIT" ]]; then
  echo "  playit-cli OK ($PLAYIT)"
else
  echo "==> Building playit agent from source (this takes a few minutes)"
  if [[ ! -d "$PLAYIT_DIR" ]]; then
    git clone https://github.com/playit-cloud/playit-agent "$PLAYIT_DIR"
  fi
  (cd "$PLAYIT_DIR" && cargo build --release)
  echo "  built $PLAYIT"
fi

echo ""
echo "==> Setup complete."
echo "Create a server:  ./create-server.sh <name>"
echo "Start it:         ./start-server.sh <name>"
