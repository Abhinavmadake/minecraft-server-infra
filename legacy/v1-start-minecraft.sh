#!/bin/zsh

# Start Minecraft server
cd ~/Desktop/server
java -Xms2G -Xmx2G -jar server.jar

# Start Playit
cd ~/playit-agent
PLAYIT_FORCE_IPV4=1 ./target/release/playit-cli
