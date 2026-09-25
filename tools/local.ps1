# Frontier Tank on this machine: PostgreSQL, the API, the game server and the web game,
# with Docker Desktop (server/docker-compose.yml). SubirLocal.cmd runs "up".
#
#   powershell -File tools/local.ps1            build and start everything, wait until it
#                                               answers and open http://localhost:8000
#                                               (the first build takes a few minutes)
#   powershell -File tools/local.ps1 status     what is running and the listed servers
#   powershell -File tools/local.ps1 logs [svc] follow the logs (api, game, web, db)
#   powershell -File tools/local.ps1 stop       stop (the game server saves everyone first)
#   powershell -File tools/local.ps1 reset      stop and ERASE the database (asks first)
#
# The first run creates server/.env from server/.env.example with random secrets and the
# test coupons on (closed tests). Edit server/.env and run again to change anything.
param([string]$Command = "up", [string]$Service = "")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root "server\.env"
$composeFile = Join-Path $root "server\docker-compose.yml"
$utf8 = New-Object System.Text.UTF8Encoding $false

function Setting([string]$Name, [string]$Default) {
    if (Test-Path -LiteralPath $envFile) {
        foreach ($line in [System.IO.File]::ReadAllLines($envFile, $utf8)) {
            if ($line -match "^$Name=(.*)$" -and $Matches[1] -ne "") { return $Matches[1] }
        }
    }
    return $Default
}

function Secret {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Make-Env {
    if (Test-Path -LiteralPath $envFile) { return }
    Write-Host "Criando server\.env (senha e chave aleatorias, cupons de teste ligados)"
    $text = [System.IO.File]::ReadAllText((Join-Path $root "server\.env.example"), $utf8)
    $text = $text -replace "(?m)^DB_PASSWORD=.*$", "DB_PASSWORD=$(Secret)"
    $text = $text -replace "(?m)^INTERNAL_KEY=.*$", "INTERNAL_KEY=$(Secret)"
    $text = $text -replace "(?m)^TEST_COUPONS=.*$", "TEST_COUPONS=1"
    $text = $text -replace "(?m)^BOT_FILL_SECONDS=.*$", "BOT_FILL_SECONDS=8"
    # UTF-8 without BOM: Docker Compose reads the file as is.
    [System.IO.File]::WriteAllText($envFile, $text, $utf8)
}

function Compose {
    & docker compose -f $composeFile @args
    if ($LASTEXITCODE -ne 0) { throw "docker compose $args falhou." }
}

function Wait-Ready {
    $url = "http://localhost:$(Setting 'WEB_PORT' '8000')"
    Write-Host -NoNewline "Esperando o servidor de jogo aparecer em $url "
    for ($i = 0; $i -lt 120; $i++) {
        try {
            $reply = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "$url/v1/servers"
            if ($reply.Content -match '"url"') {
                Write-Host ""
                Write-Host "Pronto: $url"
                return $true
            }
        } catch { }
        Write-Host -NoNewline "."
        Start-Sleep -Seconds 2
    }
    Write-Host ""
    Write-Warning "Ainda sem resposta depois de 4 minutos. Veja: powershell -File tools/local.ps1 logs"
    return $false
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker nao encontrado. Instale o Docker Desktop (https://www.docker.com/products/docker-desktop/) e abra-o antes."
}
# Windows PowerShell turns the stderr of a program into errors: checked without "Stop".
$ErrorActionPreference = "Continue"
& docker info *> $null
$running = $LASTEXITCODE -eq 0
$ErrorActionPreference = "Stop"
if (-not $running) { throw "O Docker Desktop nao esta rodando. Abra-o e tente de novo." }

switch ($Command) {
    "up" {
        Make-Env
        Compose up --build -d
        if (Wait-Ready) {
            $url = "http://localhost:$(Setting 'WEB_PORT' '8000')"
            try { Start-Process $url } catch { Write-Host "Abra no navegador: $url" }
        }
    }
    "status" {
        Compose ps
        try { (Invoke-WebRequest -UseBasicParsing "http://localhost:$(Setting 'WEB_PORT' '8000')/v1/servers").Content } catch { Write-Warning "A API nao responde na porta web." }
    }
    "logs" {
        if ($Service -ne "") { Compose logs -f --tail 100 $Service } else { Compose logs -f --tail 100 }
    }
    "stop" { Compose stop }
    "reset" {
        $answer = Read-Host "Apagar todas as contas, perfis e anuncios? Digite APAGAR"
        if ($answer -eq "APAGAR") { Compose down -v } else { Write-Host "Nada foi apagado." }
    }
    default { Get-Content -LiteralPath $PSCommandPath -TotalCount 13; exit 1 }
}
