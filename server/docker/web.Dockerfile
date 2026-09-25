# Frontier Tank web: the game exported for the browser and served by nginx, which also
# forwards /v1/ to the API and /ws to the game server (server/docker/web.nginx.conf).
# Build from the project root:  docker build -f server/docker/web.Dockerfile .
# The export has no threads (preset "Web" in export_presets.cfg), so no special headers.
FROM debian:bookworm-slim AS export
ARG GODOT_VERSION=4.7.2
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip python3 libfontconfig1 \
	&& curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
	&& unzip /tmp/godot.zip -d /opt \
	&& mv /opt/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
	&& chmod +x /usr/local/bin/godot \
	&& rm -rf /tmp/godot.zip /var/lib/apt/lists/*
WORKDIR /game
# Only the web templates (~20 MB of the 1.2 GB package), in their own layer: a new build
# of the game does not download them again.
COPY tools/web_build.py tools/web_build.py
RUN python3 tools/web_build.py templates
COPY . /game
RUN (GODOT_BIN=/usr/local/bin/godot python3 tools/web_build.py export > /tmp/export.log 2>&1 && tail -8 /tmp/export.log) \
	|| (tail -60 /tmp/export.log; exit 1)

FROM nginx:1.29-alpine
COPY server/docker/web.nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=export /game/build/web /usr/share/nginx/html
EXPOSE 80
