#!/usr/bin/env python3
"""Web build for closed tests (launch checklist, roadmap item 4).

The web build runs without threads, so it needs no SharedArrayBuffer and no
Cross-Origin-Opener-Policy / Cross-Origin-Embedder-Policy headers: any static host
works (itch.io, GitHub Pages, Netlify, a plain nginx). Preset "Web" in export_presets.cfg.

Usage:
  python tools/web_build.py templates        download only the Godot web templates
                                             (no threads, ~20 MB instead of the 1.2 GB
                                             package) into Godot's template folder
  python tools/web_build.py export [--debug] import the assets and export to build/web
  python tools/web_build.py serve [--port 8060] [--api http://localhost:8080] [--site] [--lan]
                                             serve build/web on http://localhost:8060;
                                             with --api, /v1/... goes to the API, so the
                                             game finds the servers on the page's own
                                             address (as behind the production proxy);
                                             with --site, the official website (website/)
                                             is at / and the game at /jogar/, as in the
                                             Docker stack; with --lan, prints the addresses
                                             a phone on the same Wi-Fi opens (docs/MOBILE.md)

Then open http://localhost:8060/ to play, ?bench=30 to measure the battle FPS
(tools/web_bench.mjs does it in Chromium and prints the numbers), ?fps=1 for the counter
(F3 in game), ?lang=en for English, ?touch=1 to force the touch controls on a
computer and ?api=https://... for another API.
"""
import argparse
import http.server
import io
import os
import platform
import re
import shutil
import socket
import socketserver
import ssl
import subprocess
import sys
import urllib.error
import urllib.request
import zipfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
BUILD = os.path.join(ROOT, "build", "web")
SITE = os.path.join(ROOT, "website")
GODOT_VERSION = "4.7.2"
TEMPLATE_URL = f"https://github.com/godotengine/godot/releases/download/{GODOT_VERSION}-stable/Godot_v{GODOT_VERSION}-stable_export_templates.tpz"
WANTED = ("version.txt", "web_nothreads_release.zip", "web_nothreads_debug.zip")


def godot_bin():
    found = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    if not found:
        sys.exit("Godot not found: set GODOT_BIN to the Godot 4.7 executable.")
    return found


def template_dir():
    name = f"{GODOT_VERSION}.stable"
    system = platform.system()
    if system == "Windows":
        base = os.path.join(os.environ["APPDATA"], "Godot")
    elif system == "Darwin":
        base = os.path.expanduser("~/Library/Application Support/Godot")
    else:
        base = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "godot")
    return os.path.join(base, "export_templates", name)


def ssl_context():
    bundle = os.environ.get("SSL_CERT_FILE") or os.environ.get("REQUESTS_CA_BUNDLE")
    return ssl.create_default_context(cafile=bundle) if bundle else ssl.create_default_context()


class RemoteFile(io.RawIOBase):
    """A seekable file over HTTP range requests: zipfile reads only the parts it needs."""

    def __init__(self, url):
        head = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(head, context=ssl_context()) as reply:
            self.url = reply.url
            self.size = int(reply.headers["Content-Length"])
        self.pos = 0

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else (self.pos + offset if whence == 1 else self.size + offset)
        return self.pos

    def readinto(self, buffer):
        if self.pos >= self.size or len(buffer) == 0:
            return 0
        end = min(self.size, self.pos + len(buffer)) - 1
        request = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{end}"})
        with urllib.request.urlopen(request, context=ssl_context()) as reply:
            data = reply.read()
        buffer[:len(data)] = data
        self.pos += len(data)
        return len(data)


def cmd_templates(_args):
    target = template_dir()
    os.makedirs(target, exist_ok=True)
    archive = zipfile.ZipFile(io.BufferedReader(RemoteFile(TEMPLATE_URL), buffer_size=1 << 20))
    for info in archive.infolist():
        name = os.path.basename(info.filename)
        if name in WANTED:
            print(f"{name} ({info.file_size // 1024} KB)")
            with open(os.path.join(target, name), "wb") as out:
                out.write(archive.read(info))
    print(f"Templates in {target}")


SHELL = os.path.join(ROOT, "tools", "web")


def inject_shell():
    """Mobile shell (tools/web/): viewport, full screen, rotate hint, manifest. The export's own
    viewport tag goes away: two of them is a coin toss in Safari."""
    path = os.path.join(BUILD, "index.html")
    with open(path, encoding="utf-8") as handle:
        html = handle.read()
    with open(os.path.join(SHELL, "shell_head.html"), encoding="utf-8") as handle:
        head = handle.read()
    html = re.sub(r'\s*<meta name="viewport"[^>]*>', "", html)
    if "gf-turn" not in html:
        html = html.replace("</head>", head + "</head>", 1)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(html)
    shutil.copy(os.path.join(SHELL, "manifest.webmanifest"), os.path.join(BUILD, "manifest.webmanifest"))


def cmd_export(args):
    godot = godot_bin()
    if not os.path.exists(os.path.join(template_dir(), "web_nothreads_release.zip")):
        print("Web templates missing: python tools/web_build.py templates")
    os.makedirs(BUILD, exist_ok=True)
    # Godot must not import the exported files as project assets.
    open(os.path.join(ROOT, "build", ".gdignore"), "a").close()
    subprocess.run([godot, "--headless", "--path", ROOT, "--editor", "--import", "--quit"], check=False)
    mode = "--export-debug" if args.debug else "--export-release"
    result = subprocess.run([godot, "--headless", "--path", ROOT, mode, "Web", os.path.join(BUILD, "index.html")])
    if result.returncode != 0 or not os.path.exists(os.path.join(BUILD, "index.pck")):
        sys.exit("Export failed.")
    inject_shell()
    total = 0
    for name in sorted(os.listdir(BUILD)):
        size = os.path.getsize(os.path.join(BUILD, name))
        total += size
        print(f"  {name:32} {size / 1048576:7.2f} MB")
    print(f"  {'total':32} {total / 1048576:7.2f} MB -> {BUILD}")


def run_windows(command):
    """Runs a PowerShell command on the Windows side of WSL (empty text when there is none)."""
    exe = shutil.which("powershell.exe")
    if not exe:
        return ""
    try:
        done = subprocess.run([exe, "-NoProfile", "-Command", command], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return ""
    return done.stdout.strip()


def in_wsl():
    try:
        with open("/proc/version", encoding="utf-8") as handle:
            return "microsoft" in handle.read().lower()
    except OSError:
        return False


def lan_addresses():
    """The IPv4 addresses of this computer on the local network (not the virtual adapters)."""
    found = []
    if in_wsl():
        text = run_windows("Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'vEthernet|Loopback|WSL|Bluetooth' -and $_.IPAddress -notlike '169.*' } | ForEach-Object { $_.IPAddress }")
        found = [line.strip() for line in text.splitlines() if line.strip()]
    else:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            probe.connect(("10.255.255.255", 1))
            found = [probe.getsockname()[0]]
        except OSError:
            pass
        finally:
            probe.close()
    return found


def print_lan(port, site):
    """What to type on the phone. Under WSL2 the game runs behind NAT: Windows has to forward the port."""
    addresses = lan_addresses()
    path = "/jogar/" if site else "/"
    print("")
    if not addresses:
        print("Phone: no local network address found. Connect this computer to the same Wi-Fi as the phone.")
        return
    for address in addresses:
        print(f"Phone (same Wi-Fi):  http://{address}:{port}{path}")
    if in_wsl():
        forwarded = run_windows("netsh interface portproxy show v4tov4")
        if f"{port}" not in forwarded:
            print("")
            print(f"WSL2 hides port {port} from the network. Once, in Windows: double-click Celular.cmd")
            print("(it asks for administrator rights, forwards the port and opens the firewall for private networks).")
    print("iPhone: Safari -> Share -> Add to Home Screen (full screen). Android: Chrome goes to full screen on the first touch.")
    if os.path.exists(os.path.join(ROOT, "build", "android", "gustfire.apk")):
        for address in addresses:
            print(f"Android app (APK):   http://{address}:{port}/android/gustfire.apk")
    if os.path.exists(os.path.join(ROOT, "build", "Gustfire-xcode.zip")):
        for address in addresses:
            print(f"Xcode project (Mac): http://{address}:{port}/ios/Gustfire-xcode.zip")
    print("")


def cmd_serve(args):
    api = args.api.rstrip("/") if args.api else ""

    class Handler(http.server.SimpleHTTPRequestHandler):
        extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".apk": "application/vnd.android.package-archive", ".zip": "application/zip", ".webmanifest": "application/manifest+json", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".js": "text/javascript"}

        def __init__(self, *handler_args, **kwargs):
            super().__init__(*handler_args, directory=SITE if args.site else BUILD, **kwargs)

        def translate_path(self, path):
            # The Android test build (tools/mobile_build.py android) at /android/gustfire.apk.
            if path.startswith("/android/"):
                return os.path.join(ROOT, "build", "android", os.path.basename(path.split("?")[0]))
            # The Xcode project for the Mac (tools/mobile_build.py ios).
            if path.startswith("/ios/"):
                return os.path.join(ROOT, "build", os.path.basename(path.split("?")[0]))
            # --site: the website at /, the game at /jogar/ (server/docker/web.nginx.conf).
            if args.site and (path == "/jogar" or path.startswith("/jogar/")):
                return os.path.join(BUILD, super().translate_path(path[len("/jogar"):] or "/")[len(SITE):].lstrip(os.sep))
            return super().translate_path(path)

        def end_headers(self):
            # No COOP/COEP on purpose: the build has no threads. No cache while testing.
            self.send_header("Cache-Control", "no-cache")
            super().end_headers()

        def proxy(self):
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length) if length else None
            headers = {key: value for key, value in self.headers.items() if key.lower() in ("authorization", "content-type")}
            request = urllib.request.Request(api + self.path, data=body, headers=headers, method=self.command)
            try:
                with urllib.request.urlopen(request, timeout=15) as reply:
                    status, data, kind = reply.status, reply.read(), reply.headers.get("Content-Type", "")
            except urllib.error.HTTPError as error:
                status, data, kind = error.code, error.read(), error.headers.get("Content-Type", "")
            except OSError:
                status, data, kind = 502, b'{"error":"api_unavailable"}', "application/json"
            self.send_response(status)
            if kind:
                self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if api and self.path.startswith("/v1/"):
                return self.proxy()
            return super().do_GET()

        def do_POST(self):
            if api and self.path.startswith("/v1/"):
                return self.proxy()
            self.send_error(405)

        def do_DELETE(self):
            self.do_POST()

    if not os.path.exists(os.path.join(BUILD, "index.html")):
        if not args.site:
            sys.exit("No build yet: python tools/web_build.py export")
        print("No game build yet (python tools/web_build.py export): /jogar/ will answer 404.")
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("", args.port), Handler) as server:
        game = f"http://localhost:{args.port}/jogar/" if args.site else f"http://localhost:{args.port}/"
        site = f"site http://localhost:{args.port}/, " if args.site else ""
        print(f"Gustfire web: {site}game {game}  (benchmark: ?bench=30)" + (f", API {api}" if api else ""))
        if args.lan:
            print_lan(args.port, args.site)
        server.serve_forever()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("templates")
    export = commands.add_parser("export")
    export.add_argument("--debug", action="store_true")
    serve = commands.add_parser("serve")
    serve.add_argument("--port", type=int, default=8060)
    serve.add_argument("--api", default="")
    serve.add_argument("--site", action="store_true", help="serve website/ at / and the game at /jogar/")
    serve.add_argument("--lan", action="store_true", help="print the addresses a phone on the same network opens")
    args = parser.parse_args()
    {"templates": cmd_templates, "export": cmd_export, "serve": cmd_serve}[args.command](args)


if __name__ == "__main__":
    main()
