# Frontier Tank game server: this Godot project run headless with --server.
# Build from the project root:  docker build -f server/docker/game.Dockerfile .
FROM debian:bookworm-slim AS godot
ARG GODOT_VERSION=4.7.2
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip \
	&& curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
	&& unzip /tmp/godot.zip -d /opt \
	&& mv /opt/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /opt/godot \
	&& chmod +x /opt/godot

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 \
	&& rm -rf /var/lib/apt/lists/* \
	&& useradd --create-home --uid 10001 frontier \
	&& mkdir /game && chown frontier:frontier /game
COPY --from=godot /opt/godot /usr/local/bin/godot
WORKDIR /game
COPY --chown=frontier:frontier . /game
USER frontier
# Import the assets once at build time (the server reads textures for the terrain).
RUN godot --headless --path /game --editor --import --quit > /tmp/import.log 2>&1 || (tail -50 /tmp/import.log && exit 1)
EXPOSE 7350
STOPSIGNAL SIGTERM
ENTRYPOINT ["sh", "/game/server/docker/run-game.sh"]
