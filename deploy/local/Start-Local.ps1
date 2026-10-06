[CmdletBinding()]
param([string]$ProjectName, [string]$OverrideFile)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Use-DDriveTools.ps1')
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$localDir = Join-Path $repoRoot '.local'
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Install/start Docker Desktop with Linux containers first.' }
foreach ($file in @('compose.env','api.env','seed.sql')) {
    $path = Join-Path $localDir $file
    if (-not (Test-Path -LiteralPath $path)) { throw 'Run Prepare-Local.ps1 first.' }
    if ((Get-Content -LiteralPath $path -Raw).Contains('CHANGE_ME')) { throw "Complete .local/$file first. Do not use the upstream Firebase project." }
}
function Invoke-LocalCompose {
    $ErrorActionPreference = 'Continue'
    try { & docker @composeArgs @args; $nativeExit = $LASTEXITCODE }
    finally { $ErrorActionPreference = 'Stop' }
    if ($nativeExit -ne 0) { throw 'Docker Compose failed. Configuration values have not been printed.' }
}
$composeArgs = @('compose','--project-directory',$repoRoot,'--env-file',(Join-Path $localDir 'compose.env'),'-f',(Join-Path $repoRoot 'compose.local.yml'))
if ($ProjectName) { $composeArgs += @('-p',$ProjectName) }
if ($OverrideFile) { $composeArgs += @('-f',[IO.Path]::GetFullPath($OverrideFile)) }
# -q checks the config without disclosing interpolated credentials.
Invoke-LocalCompose config -q
Invoke-LocalCompose up -d --build --wait postgres redis api
Get-Content -LiteralPath (Join-Path $localDir 'seed.sql') -Raw |
    & docker @composeArgs exec -T postgres psql -U httpsms -d httpsms -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { throw 'System-user initialization failed.' }
Invoke-LocalCompose up -d --build --wait web proxy
Invoke-LocalCompose cp proxy:/data/caddy/pki/authorities/local/root.crt (Join-Path $localDir 'home-ca.crt')
Write-Host 'Public CA exported to .local/home-ca.crt. Verify this fingerprint before installing it:'
Get-FileHash -LiteralPath (Join-Path $localDir 'home-ca.crt') -Algorithm SHA256 | Select-Object Hash
Write-Host 'Trust only this public CA on the dedicated phone and this Windows user account.'
Write-Host 'Open https://localhost:8443 after trusting the CA. See deploy/local/README.md for the firewall and phone checklist.'
