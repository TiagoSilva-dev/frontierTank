# Opens the local web server to phones on the same Wi-Fi (docs/MOBILE.md).
#
# WSL2 runs behind NAT: a server inside WSL answers on this PC only. This forwards the ports
# from the Windows network to WSL and opens ONLY those ports in the firewall, ONLY for
# addresses of the local subnet (any network profile: a cable network is "Public" until you
# say otherwise, and the rule must not depend on that). It needs administrator rights (it
# asks) and is repeated after a restart (WSL gets a new address). `-Remove` undoes it.
#
#   Celular.cmd                 ports 8060 (tools/web_build.py serve) and 8000 (tools/local.sh)
#   Celular.cmd -Ports 8060
#   Celular.cmd -Remove
param(
	[int[]]$Ports = @(8060, 8000),
	[switch]$Remove,
	[switch]$NoPause
)

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
	$again = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Ports $($Ports -join ',')"
	if ($Remove) { $again += " -Remove" }
	if ($NoPause) { $again += " -NoPause" }
	Start-Process powershell -Verb RunAs -ArgumentList $again
	exit
}

$wsl = ((wsl.exe hostname -I) -join " ").Trim().Split(" ")[0]
if (-not $Remove -and -not $wsl) {
	Write-Host "WSL not running: start it (open the Linux terminal) and run this again." -ForegroundColor Yellow
	if (-not $NoPause) { Read-Host "Enter to close" }
	exit 1
}

foreach ($port in $Ports) {
	$rule = "Gustfire celular $port"
	netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 2>$null | Out-Null
	Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
	if ($Remove) {
		Write-Host "Port $port: closed."
		continue
	}
	# Docker Desktop publishes the stack's port (8000) on the Windows network by itself: a
	# forward there would fight it. Only a port that no Windows process listens on (wslrelay
	# only listens on 127.0.0.1) needs the forward to WSL.
	$owner = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Where-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName -ne 'wslrelay' } | Select-Object -First 1
	if ($owner) {
		Write-Host "Port $port: already served by $((Get-Process -Id $owner.OwningProcess).ProcessName), only the firewall is opened."
	} else {
		netsh interface portproxy add v4tov4 listenport=$port listenaddress=0.0.0.0 connectport=$port connectaddress=$wsl | Out-Null
		Write-Host "Port $port -> WSL $wsl"
	}
	New-NetFirewallRule -DisplayName $rule -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -Profile Any -RemoteAddress LocalSubnet | Out-Null
}

if (-not $Remove) {
	$lan = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'vEthernet|Loopback|WSL|Bluetooth' -and $_.IPAddress -notlike '169.*' }
	Write-Host ""
	foreach ($address in $lan) {
		foreach ($port in $Ports) { Write-Host "  http://$($address.IPAddress):$port/" }
	}
	Write-Host ""
	Write-Host "Start the server: python tools/web_build.py serve --lan   (or tools/local.sh, port 8000 at /jogar/)"
}
if (-not $NoPause) { Read-Host "Enter to close" }
