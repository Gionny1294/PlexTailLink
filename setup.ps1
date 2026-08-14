[CmdletBinding()]
param(
    [string]$LanCidr,
    [string]$PlexUrl = "http://127.0.0.1:32400",
    [string]$PlexToken,
    [switch]$ClearCustomConnections
)

$ErrorActionPreference = "Stop"

function Stop-WithError([string]$Message) {
    Write-Error $Message
    exit 1
}

function Get-NetworkCidr([string]$Address, [int]$PrefixLength) {
    $bytes = ([System.Net.IPAddress]::Parse($Address)).GetAddressBytes()
    $remaining = $PrefixLength
    for ($index = 0; $index -lt $bytes.Length; $index++) {
        $bits = [Math]::Min(8, [Math]::Max(0, $remaining))
        $mask = if ($bits -eq 0) { 0 } else { (0xFF -shl (8 - $bits)) -band 0xFF }
        $bytes[$index] = $bytes[$index] -band $mask
        $remaining -= $bits
    }
    "$([System.Net.IPAddress]::new($bytes))/$PrefixLength"
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Stop-WithError "Run PowerShell as Administrator."
}

$tailscaleCommand = Get-Command tailscale.exe -ErrorAction SilentlyContinue
if ($tailscaleCommand) {
    $tailscaleExe = $tailscaleCommand.Source
} else {
    $candidate = Join-Path $env:ProgramFiles "Tailscale\tailscale.exe"
    if (Test-Path $candidate) { $tailscaleExe = $candidate }
    else { Stop-WithError "Tailscale is not installed or is not in PATH." }
}

& $tailscaleExe status | Out-Null
if ($LASTEXITCODE -ne 0) { Stop-WithError "Tailscale is not connected." }

$defaultRoute = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" |
    Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
if (-not $defaultRoute) { Stop-WithError "No IPv4 default route was found." }

if (-not $LanCidr) {
    $lanAddress = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $defaultRoute.InterfaceIndex |
        Where-Object { $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1
    if (-not $lanAddress) { Stop-WithError "LAN detection failed; use -LanCidr." }
    $LanCidr = Get-NetworkCidr $lanAddress.IPAddress $lanAddress.PrefixLength
}
if ($LanCidr -notmatch '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$') {
    Stop-WithError "Invalid IPv4 CIDR: $LanCidr"
}

Get-NetIPInterface -AddressFamily IPv4 |
    Where-Object ConnectionState -eq "Connected" |
    Set-NetIPInterface -Forwarding Enabled

& $tailscaleExe set "--advertise-routes=$LanCidr"
if ($LASTEXITCODE -ne 0) { Stop-WithError "Could not advertise $LanCidr." }

if (-not $PlexToken) {
    $plexRegistry = "HKCU:\Software\Plex, Inc.\Plex Media Server"
    if (Test-Path $plexRegistry) {
        $PlexToken = (Get-ItemProperty $plexRegistry -Name PlexOnlineToken -ErrorAction SilentlyContinue).PlexOnlineToken
    }
}

if ($PlexToken) {
    $PlexUrl = $PlexUrl.TrimEnd('/')
    $networks = [Uri]::EscapeDataString("$LanCidr,100.64.0.0/10")
    $token = [Uri]::EscapeDataString($PlexToken)
    Invoke-WebRequest -UseBasicParsing -Method Put -Uri "$PlexUrl/:/prefs?LanNetworksBandwidth=$networks&X-Plex-Token=$token" | Out-Null
    if ($ClearCustomConnections) {
        Invoke-WebRequest -UseBasicParsing -Method Put -Uri "$PlexUrl/:/prefs?customConnections=&X-Plex-Token=$token" | Out-Null
    }
    Write-Host "Plex LAN Networks configured: $LanCidr,100.64.0.0/10"
} else {
    Write-Warning "Plex token not found; only subnet routing was configured."
    Write-Host "Run again with -PlexToken if Plex uses another Windows account."
}

Write-Host "Subnet advertised: $LanCidr"
Write-Host "Approve it in Tailscale admin, then test Plex using its LAN address."
