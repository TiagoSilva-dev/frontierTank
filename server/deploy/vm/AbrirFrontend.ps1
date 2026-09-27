$ErrorActionPreference = 'Stop'
$ssh = 'C:\Program Files\Git\usr\bin\ssh.exe'
$key = Join-Path $env:USERPROFILE '.ssh\ssh.key'
Write-Host 'Site: http://localhost:18000/'
Write-Host 'Jogo: http://localhost:18000/jogar/'
Write-Host 'Mantenha esta janela aberta. Ctrl+C encerra o tunel.'
& $ssh -F /dev/null -i $key -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -N -L 18000:127.0.0.1:8000 ubuntu@136.248.73.212
