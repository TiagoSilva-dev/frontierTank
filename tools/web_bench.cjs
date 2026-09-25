#!/usr/bin/env node
// Measures the battle FPS of the web build in Chromium (launch checklist, roadmap item 4).
//
//   python tools/web_build.py export
//   node tools/web_bench.cjs [--seconds 30] [--headed] [--url http://host/index.html]
//
// Without --url it serves build/web itself (tools/web_build.py serve). It opens
// index.html?bench=<seconds>, which starts a 4v4 battle played by the AI on both sides
// (PerfProbe), waits for window.ftBench and prints the result as JSON, with the WebGL
// renderer. Headless Chromium draws with SwiftShader (on the CPU), which is slower than
// any real graphics card: use --headed on a machine with a GPU for the numbers players see.
// Needs Playwright (npm i -g playwright; the Chromium it downloads, or PLAYWRIGHT_BROWSERS_PATH).

const { spawn, execSync } = require("child_process");
const path = require("path");

function loadPlaywright() {
  try {
    return require("playwright");
  } catch (error) {
    const globalRoot = execSync("npm root -g").toString().trim();
    return require(path.join(globalRoot, "playwright"));
  }
}

function option(name, fallback) {
  const index = process.argv.indexOf("--" + name);
  if (index < 0) return fallback;
  const value = process.argv[index + 1];
  return value === undefined || value.startsWith("--") ? true : value;
}

async function waitForServer(url, deadline) {
  while (Date.now() < deadline) {
    try {
      const reply = await fetch(url, { method: "HEAD" });
      if (reply.ok) return;
    } catch (error) {}
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("web server did not start: " + url);
}

async function main() {
  const seconds = Number(option("seconds", 30));
  const headed = option("headed", false) === true;
  let url = option("url", "");
  let server = null;
  if (!url) {
    const port = Number(option("port", 8061));
    const python = process.platform === "win32" ? "python" : "python3";
    server = spawn(python, [path.join(__dirname, "web_build.py"), "serve", "--port", String(port)], { stdio: "ignore" });
    url = `http://localhost:${port}/index.html`;
    await waitForServer(url, Date.now() + 15000);
  }
  const { chromium } = loadPlaywright();
  const args = headed ? ["--ignore-gpu-blocklist"] : ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"];
  const browser = await chromium.launch({ headless: !headed, args });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
    const logs = [];
    page.on("console", (message) => logs.push(message.text()));
    page.on("pageerror", (error) => logs.push("pageerror: " + error.message));
    const started = Date.now();
    await page.goto(`${url}${url.includes("?") ? "&" : "?"}bench=${seconds}`);
    const webgl = await page.evaluate(() => {
      const gl = document.createElement("canvas").getContext("webgl2");
      if (!gl) return "no WebGL2";
      const info = gl.getExtension("WEBGL_debug_renderer_info");
      return info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
    });
    await page.waitForFunction(() => window.ftBench !== undefined, null, { timeout: (seconds + 180) * 1000, polling: 500 });
    const result = await page.evaluate(() => window.ftBench);
    result.webgl = webgl;
    result.headless = !headed;
    result.load_and_run_seconds = Math.round((Date.now() - started) / 100) / 10;
    console.log(JSON.stringify(result, null, 2));
    const errors = logs.filter((line) => /error/i.test(line) && !/resources still in use/i.test(line));
    if (errors.length) console.error("Console errors:\n" + errors.slice(0, 20).join("\n"));
  } finally {
    await browser.close();
    if (server) server.kill();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
