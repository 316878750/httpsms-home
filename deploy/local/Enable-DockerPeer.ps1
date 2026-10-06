[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Use-DDriveTools.ps1')
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as administrator after Protect-DockerLanPort.ps1.' }
if (@(Get-NetFirewallProfile | Where-Object { -not $_.Enabled }).Count) { throw 'Windows firewall must remain enabled for all profiles.' }
$configPath = Join-Path $repoRoot '.local/compose.env'
$lines = @(Get-Content -LiteralPath $configPath)
$lanIP = (($lines | Where-Object { $_ -match '^HTTPSMS_LAN_IP=' }) -split '=',2)[1].Trim()
$lanCidr = (($lines | Where-Object { $_ -match '^HTTPSMS_LAN_CIDR=' }) -split '=',2)[1].Trim()
$rules = @{
    Block='httpSMS-8444-Block-Outside-Home'
    Allow='httpSMS-8444-Allow-Home'
}
foreach ($kind in $rules.Keys) {
    $rule = Get-NetFirewallRule -Name $rules[$kind] -ErrorAction Stop
    $ports = $rule | Get-NetFirewallPortFilter
    $addresses = $rule | Get-NetFirewallAddressFilter
    if ($rule.Enabled -ne 'True' -or $rule.Direction -ne 'Inbound' -or $rule.Action -ne $kind -or $rule.Profile -ne 'Any' -or $ports.LocalPort -ne '8444' -or $ports.Protocol -ne 'TCP' -or $addresses.LocalAddress -notcontains $lanIP) { throw 'Firewall rules do not match this deployment.' }
    if ($kind -eq 'Allow' -and $addresses.RemoteAddress -notcontains $lanCidr) { throw 'Home allow rule has a different subnet.' }
    if ($kind -eq 'Block') {
        if ($lanCidr -notmatch '^([0-9.]+)/24$') { throw 'This firewall workflow requires /24.' }
        $b = [Net.IPAddress]::Parse($Matches[1]).GetAddressBytes()
        $n = [long]$b[0]*16777216 + [long]$b[1]*65536 + [long]$b[2]*256 + $b[3]
        function Address([long]$v) { '{0}.{1}.{2}.{3}' -f (($v -shr 24)-band 255),(($v -shr 16)-band 255),(($v -shr 8)-band 255),($v-band 255) }
        $expected = @()
        $expected += '0.0.0.0-' + (Address ($n-1))
        $expected += (Address ($n+256)) + '-255.255.255.255'
        foreach ($range in $expected) { if ($addresses.RemoteAddress -notcontains $range) { throw 'Outside-home block rule does not cover the expected ranges.' } }
    }
}
$compose = @('compose','--project-directory',$repoRoot,'--env-file',$configPath,'-f',(Join-Path $repoRoot 'compose.local.yml'))
$container = & docker @compose ps -q proxy
if ($LASTEXITCODE -ne 0 -or -not $container) { throw 'Start the local proxy first.' }
$networks = (& docker inspect --format '{{json .NetworkSettings.Networks}}' $container) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect Docker networking.' }
$edge = @($networks.PSObject.Properties | Where-Object { $_.Name.EndsWith('_edge') })
if ($edge.Count -ne 1) { throw 'Expected one edge network; inspect manually.' }
$peer = $edge[0].Value.Gateway
if (-not $peer -or $peer -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'No IPv4 Docker gateway found.' }
$lines = @($lines | Where-Object { $_ -notmatch '^HTTPSMS_DOCKER_PEER=' })
$lines += "HTTPSMS_DOCKER_PEER=$peer"
[IO.File]::WriteAllText($configPath, ($lines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
$ErrorActionPreference = 'Continue'
try { & docker @compose up -d --no-deps --force-recreate proxy; $nativeExit=$LASTEXITCODE }
finally { $ErrorActionPreference = 'Stop' }
if ($nativeExit -ne 0) { throw 'Could not recreate the proxy.' }
Write-Host 'Docker edge gateway configured after validating home-only firewall rules. Recheck phone connectivity.'
