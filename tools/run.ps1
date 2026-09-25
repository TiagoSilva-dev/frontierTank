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
    exit $LASTEXITCODE
} elseif ($Editor) {
    & $godotBinary --path $projectRoot --editor
} else {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.godot\global_script_class_cache.cfg'))) {
        & $godotBinary --headless --path $projectRoot --editor --import --quit
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    & $godotBinary --path $projectRoot
}
