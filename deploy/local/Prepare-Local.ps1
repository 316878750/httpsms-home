[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LanIP,
    [Parameter(Mandatory)][string]$LanCidr
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$localDir = Join-Path $repoRoot '.local'
$address = [Net.IPAddress]::Parse($LanIP)
if ($address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'Use the home LAN IPv4 address.' }
$bytes = $address.GetAddressBytes()
$private = $bytes[0] -eq 10 -or ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or ($bytes[0] -eq 192 -and $bytes[1] -eq 168)
if (-not $private) { throw 'Only RFC1918 home LAN addresses are allowed.' }
if ($LanCidr -notmatch '^(\d{1,3}\.){3}\d{1,3}/(\d|[12]\d|3[0-2])$') { throw 'Supply a LAN CIDR such as 192.168.1.0/24.' }
if (-not $LanCidr.EndsWith('/24')) { throw 'The included Windows firewall workflow supports /24 home networks only.' }
$network, $prefix = $LanCidr.Split('/')
$networkBytes = [Net.IPAddress]::Parse($network).GetAddressBytes()
if ($networkBytes.Length -ne 4 -or $networkBytes[3] -ne 0 -or $bytes[3] -eq 0 -or $bytes[3] -eq 255) { throw 'Use a canonical /24 network and a usable host address.' }
if ([int]$prefix -lt 8) { throw 'The allowed LAN subnet is too broad.' }
if (($bytes[0] -eq 172 -and [int]$prefix -lt 12) -or ($bytes[0] -eq 192 -and [int]$prefix -lt 16)) { throw 'LanCidr must stay inside a private IPv4 range.' }
for ($i=0; $i -lt 4; $i++) {
    $bits = [Math]::Min(8, [Math]::Max(0, [int]$prefix - 8*$i))
    $mask = if ($bits -eq 0) { 0 } else { (255 -shl (8-$bits)) -band 255 }
    if (($bytes[$i] -band $mask) -ne ($networkBytes[$i] -band $mask)) { throw 'LanIP must belong to LanCidr.' }
}
if (Test-Path -LiteralPath (Join-Path $localDir 'compose.env')) { throw 'Local configuration already exists. Edit it explicitly; secrets were not overwritten.' }
New-Item -ItemType Directory -Force -Path $localDir | Out-Null
# Limit secrets to the current Windows account and SYSTEM; do not print their values.
$accountSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $localDir /inheritance:r /grant:r "*$($accountSid):(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not protect the local configuration directory.' }
function New-LocalSecret {
    $secretBytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($secretBytes) } finally { $rng.Dispose() }
    return [BitConverter]::ToString($secretBytes).Replace('-', '').ToLowerInvariant()
}
$databasePassword = New-LocalSecret
$redisPassword = New-LocalSecret
$systemKey = New-LocalSecret
$systemUser = [Guid]::NewGuid().ToString()
@"
HTTPSMS_LAN_IP=$LanIP
HTTPSMS_LAN_CIDR=$LanCidr
POSTGRES_PASSWORD=$databasePassword
REDIS_PASSWORD=$redisPassword
SYSTEM_USER_ID=$systemUser
SYSTEM_API_KEY=$systemKey
FIREBASE_API_KEY=CHANGE_ME
FIREBASE_AUTH_DOMAIN=CHANGE_ME
FIREBASE_PROJECT_ID=CHANGE_ME
FIREBASE_APP_ID=CHANGE_ME
FIREBASE_MESSAGING_SENDER_ID=CHANGE_ME
"@ | Set-Content -LiteralPath (Join-Path $localDir 'compose.env') -Encoding utf8
@'
GCP_PROJECT_ID=CHANGE_ME
# Put your own service-account JSON on one line inside single quotes.
FIREBASE_CREDENTIALS='CHANGE_ME'
SMTP_FROM_NAME=httpSMS Local
SMTP_FROM_EMAIL=httpsms@localhost
SMTP_HOST=127.0.0.1
SMTP_PORT=25
SMTP_USERNAME=
SMTP_PASSWORD=
'@ | Set-Content -LiteralPath (Join-Path $localDir 'api.env') -Encoding utf8
"INSERT INTO users (id, api_key, email) VALUES ('$systemUser', '$systemKey', 'system@localhost') ON CONFLICT (id) DO NOTHING;" |
    Set-Content -LiteralPath (Join-Path $localDir 'seed.sql') -Encoding utf8
# Trust user-installed CAs only for the chosen home server, never for every domain.
$xmlPath = Join-Path $repoRoot 'android/app/src/main/res/xml/network_security_config.xml'
$xml = New-Object System.Xml.XmlDocument
$xml.PreserveWhitespace = $true
$xml.Load($xmlPath)
$domainConfig = $xml.SelectSingleNode('/network-security-config/domain-config')
$existingIP = @($domainConfig.SelectNodes('domain')) | Where-Object { $_.InnerText -match '^\d+\.' }
foreach ($node in $existingIP) { [void]$domainConfig.RemoveChild($node) }
$domain = $xml.CreateElement('domain')
$domain.SetAttribute('includeSubdomains', 'false')
$domain.InnerText = $LanIP
[void]$domainConfig.PrependChild($domain)
$xml.Save($xmlPath)
$stringsPath = Join-Path $repoRoot 'android/app/src/main/res/values/strings.xml'
$stringsXml = New-Object System.Xml.XmlDocument
$stringsXml.PreserveWhitespace = $true
$stringsXml.Load($stringsPath)
$stringsXml.SelectSingleNode('/resources/string[@name="default_server_url"]').InnerText = "https://${LanIP}:8444"
$stringsXml.Save($stringsPath)
Write-Host 'Local templates created in .local (credentials were not printed).'
Write-Host 'Fill in your own Firebase configuration, then run Start-Local.ps1.'
Write-Host "Phone endpoint: https://${LanIP}:8444 ; computer UI: https://localhost:8443"
Write-Host 'Reserve this computer IP in the router before building the Android app.'
