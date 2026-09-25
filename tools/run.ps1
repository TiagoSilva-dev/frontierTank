param([switch]$Editor, [switch]$Test)
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
$godotBinary = if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif ($godotCommand) { $godotCommand.Source } else { Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $godotBinary)) { throw 'Godot não encontrado. Configure GODOT_BIN com o caminho do executável Godot 4.7.' }
if ($Test) {
    & $godotBinary --headless --path $projectRoot --editor --import --quit
    & $godotBinary --headless --path $projectRoot --script tests/combat_tests.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $godotBinary --headless --path $projectRoot --script tests/ui_tests.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $godotBinary --headless --path $projectRoot --script tests/pve_tests.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $godotBinary --headless --path $projectRoot --script tests/armory_tests.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $godotBinary --headless --path $projectRoot --script tests/pow_tests.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $godotBinary --headless --path $projectRoot --script tests/craft_tests.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $godotBinary --headless --path $projectRoot --script tests/i18n_tests.gd
    exit $LASTEXITCODE
} elseif ($Editor) {
    & $godotBinary --path $projectRoot --editor
} else {
    # Import again whenever art, audio or scripts are newer than the last import, so new
    # assets (like the 0.7 sounds and music) load without opening the editor.
    $stamp = Join-Path $projectRoot '.godot\import_stamp'
    $needImport = -not (Test-Path -LiteralPath (Join-Path $projectRoot '.godot\global_script_class_cache.cfg')) -or -not (Test-Path -LiteralPath $stamp)
    if (-not $needImport) {
        $since = (Get-Item -LiteralPath $stamp).LastWriteTime
        $newer = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'assets'), (Join-Path $projectRoot 'client') -Recurse -File | Where-Object { $_.LastWriteTime -gt $since } | Select-Object -First 1
        $needImport = $null -ne $newer
    }
    if ($needImport) {
        & $godotBinary --headless --path $projectRoot --editor --import --quit
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        New-Item -ItemType File -Force -Path $stamp | Out-Null
    }
    & $godotBinary --path $projectRoot
}
