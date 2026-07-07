# minecraft-server-infra

Scripts and operational notes from self-hosting Minecraft servers on a Mac
(Apple Silicon) for about six months — multiple server instances (vanilla,
Purpur, Forge modded), made reachable from the internet without router port
forwarding, and kept alive and tuned on constrained consumer hardware.

The worlds and server jars themselves aren't in this repo; this is the
infrastructure around them.

## The problem

Friends couldn't connect to a server running on a home network behind
CGNAT — there was no public IP to port-forward to. The fix was a reverse
tunnel through [playit.gg](https://playit.gg): a lightweight agent on the
Mac holds an outbound connection to playit's edge, which gives the server a
stable public address.

```
players ──▶ playit.gg edge ──▶ outbound tunnel ──▶ playit-cli (Mac) ──▶ localhost:2556x (server)
```

One wrinkle: playit.gg ships no native macOS ARM binary, so the agent is
built from source with cargo:

```sh
git clone https://github.com/playit-cloud/playit-agent ~/playit-agent
cd ~/playit-agent
cargo build --release   # → target/release/playit-cli (arm64 Mach-O)
```

## Quick start

```sh
./setup.sh                    # one-time: installs JDKs, tmux, Rust; builds playit
./create-server.sh survival   # scaffold a server (latest Purpur, EULA prompt)
./start-server.sh survival    # run it (server + tunnel in a tmux session)
./stop-server.sh survival     # graceful shutdown (saves the world first)
```

## Layout

```
setup.sh           # dependency check/install + playit source build
create-server.sh   # downloads a Purpur jar, writes tuned config + .env entry
start-server.sh    # launcher: server + tunnel in a two-pane tmux session
stop-server.sh     # sends `stop` to the console, waits, closes the session
servers/*.env      # per-server config (session, dir, jar, heap, Java version)
legacy/            # earlier script versions, kept as an evolution record
```

Java versions are resolved per server: Minecraft 1.20.5–1.21.x needs Java 21
while 26.1+ needs Java 25+, so each server's `.env` pins its own
`JAVA_VERSION` and the launcher finds a matching JDK (via `java_home` or
Homebrew kegs).

The launcher puts the server console in one tmux pane and the tunnel agent
in the other, so both survive the terminal closing and the console stays
reachable for admin commands. Re-running it attaches to the existing session
instead of double-starting. See [legacy/README.md](legacy/README.md) for how
it got here — v1 had a bug where the tunnel only started after the server
*exited*.

## Performance notes

Running a JVM game server next to daily-driver workloads on a laptop meant
tuning mattered:

- **Fixed heap** (`-Xms` = `-Xmx`, 4 GB) so the JVM never stalls resizing
  the heap mid-session.
- **G1GC with `MaxGCPauseMillis=200`** — GC pauses longer than a tick
  (50 ms) show up as visible lag spikes; G1's pause target keeps them
  bounded and predictable.
- **[Purpur](https://purpurmc.org/)** (a Paper fork) instead of the vanilla
  jar for its performance patches and tunables.
- **High `view-distance` (24) with low `simulation-distance` (5)** — players
  see far, but entity/redstone ticking stays cheap. Render distance is
  mostly a network/memory cost; simulation distance is the CPU cost.
- **[Spark](https://spark.lucko.me/)** profiler installed on the servers to
  check tick timings and find what actually caused lag, rather than guessing.

## What ran on this

- A long-running Purpur survival server (Minecraft 1.21.10, upgraded in
  place to 1.21.11 preserving ~6 GB of world data across three dimensions).
- A Forge 1.20.1 modded server (GeckoLib-based mods) — with its share of
  startup crashes to debug.
- An earlier Java + Bedrock cross-play instance.
