[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LanIP,
    [Parameter(Mandatory)][string]$LanCidr
)
$ErrorActionPreference = 'Stop'
# Docker Desktop rewrites source addresses. Enforce the real source boundary on
# Windows before trusting the observed Docker gateway in Caddy.
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script as administrator.'
}
function To-Number([string]$Address) {
    $bytes = ([Net.IPAddress]::Parse($Address)).GetAddressBytes()
    if ($bytes.Length -ne 4) { throw 'IPv4 is required.' }
    return [long]$bytes[0]*16777216 + [long]$bytes[1]*65536 + [long]$bytes[2]*256 + $bytes[3]
}
function To-Address([long]$Value) {
    return '{0}.{1}.{2}.{3}' -f (($Value -shr 24) -band 255), (($Value -shr 16) -band 255), (($Value -shr 8) -band 255), ($Value -band 255)
}
$parts = $LanCidr.Split('/')
if ($parts.Length -ne 2 -or $parts[1] -ne '24') { throw 'This home deployment requires an explicit /24 subnet.' }
$first = To-Number $parts[0]
$hostAddress = To-Number $LanIP
if (($first % 256) -ne 0 -or $hostAddress -le $first -or $hostAddress -ge ($first+255)) { throw 'LAN address/subnet mismatch.' }
if ($LanIP -notmatch '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)') { throw 'A private LAN address is required.' }
$blockName = 'httpSMS-8444-Block-Outside-Home'
$allowName = 'httpSMS-8444-Allow-Home'
foreach ($name in @($blockName,$allowName)) {
    if (Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue) { throw "Rule $name already exists; inspect it before changing it." }
}
# Explicit blocks take precedence over Docker Desktop's broad allow rules.
$outside = @(
    ('0.0.0.0-' + (To-Address ($first-1)))
    ((To-Address ($first+256)) + '-255.255.255.255')
)
New-NetFirewallRule -Name $blockName -DisplayName $blockName -Direction Inbound -Action Block -Enabled True -Profile Any -Protocol TCP -LocalAddress $LanIP -LocalPort 8444 -RemoteAddress $outside | Out-Null
New-NetFirewallRule -Name $allowName -DisplayName $allowName -Direction Inbound -Action Allow -Enabled True -Profile Any -Protocol TCP -LocalAddress $LanIP -LocalPort 8444 -RemoteAddress $LanCidr | Out-Null
Write-Output 'Home-only firewall rules installed for TCP 8444. Loopback web port is unchanged.'
