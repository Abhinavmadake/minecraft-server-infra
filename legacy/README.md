# Script evolution

These are the original launch scripts, kept as a record of how the setup
evolved. Each version fixed a real problem with the previous one.

**v1 — `v1-start-minecraft.sh`.** Runs the server, then starts the tunnel
agent. The bug: the server runs in the foreground, so the tunnel only ever
started *after the server shut down*. Players could never actually connect
while it was written this way.

**v2 — `v2-start-server-*.sh`.** Backgrounds the server with `&`, sleeps 8
seconds so it can bind its port, then starts the tunnel (with an IPv4 force
flag to work around an agent networking issue). This worked, but closing the
terminal killed everything, and the server console was no longer reachable
for admin commands.

**v3 — `v3-start-*.sh`.** tmux orchestration: the server and the tunnel run
in two panes of a detached session, so both survive terminal closes, the
console stays accessible, and re-running the script reattaches instead of
double-starting. Also adds a `TMUX_TMPDIR` fix for a macOS socket-permission
issue, pins Java 21, and adds JVM heap/GC flags.

The two v3 scripts were near-identical copies per server — the current
`start-server.sh` at the repo root replaces them with one parameterized
script plus per-server `.env` files.
