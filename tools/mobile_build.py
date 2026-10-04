#!/usr/bin/env python3
"""Android and iOS builds for the phone tests (docs/MOBILE.md). No store involved: the APK is
installed from a link or a cable, the Xcode project runs on your own iPhone.

Usage:
  python tools/mobile_build.py templates          download the Android and iOS export templates
                                                  (~400 MB, read out of Godot's 1.2 GB package
                                                  with range requests) into Godot's template folder
  python tools/mobile_build.py setup-android --accept-licenses
                                                  the Android SDK (command-line tools, platform
                                                  tools, build tools, platform) in $ANDROID_HOME
                                                  or ~/Android/Sdk, a debug keystore, and the
                                                  paths in Godot's editor settings. --accept-licenses
                                                  accepts the Android SDK licenses for you: read them first
                                                  (https://developer.android.com/studio/terms)
  python tools/mobile_build.py android [--api http://<ip>:8000]
                                                  import and export build/android/gustfire.apk.
                                                  --api bakes the address of the API the phone
                                                  talks to (the default, localhost, is the phone
                                                  itself): your computer's address on the Wi-Fi
  python tools/mobile_build.py install            adb install -r of that APK on a phone (USB
                                                  debugging or `adb pair` over Wi-Fi)
  python tools/mobile_build.py ios [--team ID] [--bundle com.you.gustfire] [--api http://<ip>:8000]
                                                  export the Xcode project to build/ios/ and zip it
                                                  (build/Gustfire-xcode.zip). On the Mac: unzip, open
                                                  Gustfire.xcodeproj, Signing & Capabilities -> your
                                                  team, plug in the iPhone, Run. A free Apple ID works
                                                  (the app expires after 7 days). Apple wants a bundle
                                                  id nobody else registered: --bundle changes it

  python tools/mobile_build.py share [--stop]     serve the APK and the Xcode zip with a small nginx
                                                  container (gustfire-downloads, port 8062). With
                                                  Docker Desktop on Windows the port reaches the Wi-Fi
                                                  by itself (no administrator step); open
                                                  http://<ip>:8062/gustfire.apk on the phone and
                                                  http://<ip>:8062/Gustfire-xcode.zip on the Mac

`python tools/web_build.py serve --lan` serves the same two files at /android/gustfire.apk and
/ios/Gustfire-xcode.zip, for a computer whose ports the phone can already reach.
"""
import argparse
import io
import os
import re
import shutil
import subprocess
import sys
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(__file__))
import web_build  # noqa: E402  (RemoteFile, template_dir, godot_bin)

ROOT = web_build.ROOT
ANDROID_OUT = os.path.join(ROOT, "build", "android")
IOS_OUT = os.path.join(ROOT, "build", "ios")
TEMPLATES = ("android_debug.apk", "android_release.apk", "ios.zip", "version.txt")
SDK_PACKAGES = ("platform-tools", "build-tools;35.0.1", "platforms;android-35")
REPOSITORY = "https://dl.google.com/android/repository/"
KEYSTORE = os.path.expanduser("~/.local/share/godot/keystores/debug.keystore")


def sdk_root():
    return os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or os.path.expanduser("~/Android/Sdk")


def java_home():
    found = os.environ.get("JAVA_HOME")
    if found:
        return found
    java = shutil.which("java")
    if not java:
        sys.exit("Java not found: install a JDK (17 or newer), e.g. `sudo apt install openjdk-17-jdk-headless`.")
    return os.path.dirname(os.path.dirname(os.path.realpath(java)))


def cmd_templates(_args):
    target = web_build.template_dir()
    os.makedirs(target, exist_ok=True)
    archive = zipfile.ZipFile(io.BufferedReader(web_build.RemoteFile(web_build.TEMPLATE_URL), buffer_size=1 << 20))
    for info in archive.infolist():
        name = os.path.basename(info.filename)
        if name not in TEMPLATES:
            continue
        path = os.path.join(target, name)
        if os.path.exists(path) and os.path.getsize(path) == info.file_size:
            print(f"{name} already there")
            continue
        print(f"{name} ({info.file_size // 1048576} MB)", flush=True)
        with archive.open(info) as source, open(path, "wb") as out:
            shutil.copyfileobj(source, out, 1 << 20)
    print(f"Templates in {target}")


def fetch(url, path):
    print(f"download {url}", flush=True)
    with urllib.request.urlopen(url, context=web_build.ssl_context()) as reply, open(path, "wb") as out:
        shutil.copyfileobj(reply, out, 1 << 20)


def cmd_setup_android(args):
    if not args.accept_licenses:
        sys.exit("The Android SDK installs under Google's licenses (https://developer.android.com/studio/terms).\nRead them and run again with --accept-licenses.")
    root = sdk_root()
    manager = os.path.join(root, "cmdline-tools", "latest", "bin", "sdkmanager")
    if not os.path.exists(manager):
        listing = urllib.request.urlopen(REPOSITORY + "repository2-3.xml", context=web_build.ssl_context()).read().decode("utf-8")
        builds = sorted({int(n) for n in re.findall(r"commandlinetools-linux-(\d+)_latest\.zip", listing)})
        if not builds:
            sys.exit("Could not find the Android command-line tools in Google's repository.")
        os.makedirs(root, exist_ok=True)
        archive = os.path.join(root, "cmdline-tools.zip")
        fetch(f"{REPOSITORY}commandlinetools-linux-{builds[-1]}_latest.zip", archive)
        extracted = os.path.join(root, "cmdline-tools", "_unpack")
        shutil.rmtree(extracted, ignore_errors=True)
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(extracted)
        os.replace(os.path.join(extracted, "cmdline-tools"), os.path.join(root, "cmdline-tools", "latest"))
        shutil.rmtree(extracted, ignore_errors=True)
        os.remove(archive)
        for name in os.listdir(os.path.join(root, "cmdline-tools", "latest", "bin")):
            os.chmod(os.path.join(root, "cmdline-tools", "latest", "bin", name), 0o755)
    env = dict(os.environ, JAVA_HOME=java_home())
    # Google's newer tools route sdkmanager to the `android` CLI, which sends usage metrics
    # unless told not to: call it directly with --no-metrics when it is there.
    cli = os.path.join(root, "cmdline-tools", "latest", "bin", "android")
    if os.path.exists(cli):
        subprocess.run([cli, "--no-metrics", f"--sdk={root}", "sdk", "install", *SDK_PACKAGES], input=("y\n" * 20).encode(), env=env, check=True)
    else:
        subprocess.run([manager, f"--sdk_root={root}", "--licenses"], input=("y\n" * 60).encode(), env=env, check=False, stdout=subprocess.DEVNULL)
        subprocess.run([manager, f"--sdk_root={root}", *SDK_PACKAGES], input=("y\n" * 20).encode(), env=env, check=True)
    make_keystore()
    write_editor_settings(root)
    print(f"Android SDK ready in {root}")


def make_keystore():
    if os.path.exists(KEYSTORE):
        return
    os.makedirs(os.path.dirname(KEYSTORE), exist_ok=True)
    keytool = os.path.join(java_home(), "bin", "keytool")
    subprocess.run([keytool, "-genkeypair", "-v", "-keystore", KEYSTORE, "-storepass", "android", "-alias", "androiddebugkey", "-keypass", "android",
                    "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000", "-dname", "CN=Android Debug,O=Android,C=US"], check=True, stdout=subprocess.DEVNULL)


def editor_settings_path():
    base = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    return os.path.join(base, "godot", f"editor_settings-{web_build.GODOT_VERSION.rsplit('.', 1)[0]}.tres")


def write_editor_settings(root):
    """Godot reads the SDK, the JDK and the debug keystore from its editor settings."""
    path = editor_settings_path()
    wanted = {
        "export/android/android_sdk_path": root,
        "export/android/java_sdk_path": java_home(),
        "export/android/debug_keystore": KEYSTORE,
        "export/android/debug_keystore_user": "androiddebugkey",
        "export/android/debug_keystore_pass": "android",
    }
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        text = '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    else:
        text = open(path, encoding="utf-8").read()
    for key, value in wanted.items():
        line = f'{key} = "{value}"'
        pattern = re.compile(r"^" + re.escape(key) + r" = .*$", re.M)
        text = pattern.sub(lambda _m: line, text) if pattern.search(text) else text.rstrip("\n") + "\n" + line + "\n"
    open(path, "w", encoding="utf-8").write(text)
    print(f"Godot editor settings updated: {path}")


def export(preset, target, release, extra=None, product=None):
    godot = web_build.godot_bin()
    os.makedirs(os.path.dirname(target), exist_ok=True)
    open(os.path.join(ROOT, "build", ".gdignore"), "a").close()
    subprocess.run([godot, "--headless", "--path", ROOT, "--editor", "--import", "--quit"], check=False)
    mode = "--export-release" if release else "--export-debug"
    result = subprocess.run([godot, "--headless", "--path", ROOT, mode, preset, target, *(extra or [])])
    # The iOS export leaves an Xcode project, not the .ipa (that is built on the Mac).
    product = product or target
    if result.returncode != 0 or not os.path.exists(product):
        sys.exit(f"Export of {preset} failed (see the messages above; `templates` and `setup-android` come first).")
    if os.path.isfile(product):
        print(f"{product}  {os.path.getsize(product) / 1048576:.1f} MB")


def bake_api(url):
    """The API the build talks to (client/net/auth_client.gd default_api reads this file)."""
    path = os.path.join(ROOT, "api_default.txt")
    if url:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(url.strip() + "\n")
    if os.path.exists(path):
        print(f"API baked into the build: {open(path, encoding='utf-8').read().strip()}")
    else:
        print("No --api: the build talks to http://localhost:8080 (itself), so only offline mode works.")


def cmd_android(args):
    bake_api(args.api)
    export("Android", os.path.join(ANDROID_OUT, "gustfire.apk"), False)


def adb():
    path = os.path.join(sdk_root(), "platform-tools", "adb")
    if not os.path.exists(path):
        sys.exit("adb not found: python tools/mobile_build.py setup-android --accept-licenses")
    return path


def cmd_install(_args):
    apk = os.path.join(ANDROID_OUT, "gustfire.apk")
    if not os.path.exists(apk):
        sys.exit("No APK yet: python tools/mobile_build.py android")
    subprocess.run([adb(), "devices"], check=True)
    subprocess.run([adb(), "install", "-r", apk], check=True)


def cmd_ios(args):
    # The team id is the 10 characters Xcode shows for your Apple ID (Settings > Accounts).
    # Exporting only needs some value: Xcode asks for the real team when it signs.
    path = os.path.join(ROOT, "export_presets.cfg")
    text = open(path, encoding="utf-8").read()
    if args.team:
        text = re.sub(r'application/app_store_team_id="[^"]*"', f'application/app_store_team_id="{args.team}"', text)
    if args.bundle:
        text = re.sub(r'application/bundle_identifier="[^"]*"', f'application/bundle_identifier="{args.bundle}"', text)
    open(path, "w", encoding="utf-8").write(text)
    bake_api(args.api)
    shutil.rmtree(IOS_OUT, ignore_errors=True)
    export("iOS", os.path.join(IOS_OUT, "Gustfire.ipa"), False, product=os.path.join(IOS_OUT, "Gustfire.xcodeproj"))
    archive = os.path.join(ROOT, "build", "Gustfire-xcode")
    shutil.make_archive(archive, "zip", IOS_OUT)
    print(f"{archive}.zip  {os.path.getsize(archive + '.zip') / 1048576:.1f} MB  (open Gustfire.xcodeproj on the Mac)")


SHARE_NAME = "gustfire-downloads"
SHARE_PORT = 8062


def cmd_share(args):
    subprocess.run(["docker", "rm", "-f", SHARE_NAME], capture_output=True)
    if args.stop:
        print(f"{SHARE_NAME} removed.")
        return
    folder = os.path.join(ROOT, "build", "dl")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    shared = []
    for source in (os.path.join(ANDROID_OUT, "gustfire.apk"), os.path.join(ROOT, "build", "Gustfire-xcode.zip")):
        if os.path.exists(source):
            target = os.path.join(folder, os.path.basename(source))
            try:
                os.link(source, target)
            except OSError:
                shutil.copy(source, target)
            shared.append(os.path.basename(source))
    if not shared:
        sys.exit("Nothing to share: python tools/mobile_build.py android (and ios) first.")
    subprocess.run(["docker", "run", "-d", "--restart", "unless-stopped", "--name", SHARE_NAME, "-p", f"{SHARE_PORT}:80",
                    "-v", f"{folder}:/usr/share/nginx/html:ro", "nginx:1.29-alpine"], check=True, stdout=subprocess.DEVNULL)
    for address in web_build.lan_addresses() or ["<ip>"]:
        for name in shared:
            print(f"http://{address}:{SHARE_PORT}/{name}")
    print(f"Stop with: python tools/mobile_build.py share --stop")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("templates")
    setup = commands.add_parser("setup-android")
    setup.add_argument("--accept-licenses", action="store_true")
    android = commands.add_parser("android")
    android.add_argument("--api", default="")
    commands.add_parser("install")
    share = commands.add_parser("share")
    share.add_argument("--stop", action="store_true")
    ios = commands.add_parser("ios")
    ios.add_argument("--team", default="")
    ios.add_argument("--bundle", default="")
    ios.add_argument("--api", default="")
    args = parser.parse_args()
    {"templates": cmd_templates, "setup-android": cmd_setup_android, "android": cmd_android, "install": cmd_install, "share": cmd_share, "ios": cmd_ios}[args.command](args)


if __name__ == "__main__":
    main()
