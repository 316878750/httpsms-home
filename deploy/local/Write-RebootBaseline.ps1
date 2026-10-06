[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Use-DDriveTools.ps1')
$config = Join-Path $repoRoot '.local/compose.env'
$ErrorActionPreference = 'Continue'
try { $count = & docker compose --project-directory $repoRoot --env-file $config -f (Join-Path $repoRoot 'compose.local.yml') exec -T postgres psql -U httpsms -d httpsms -Atc 'SELECT count(*) FROM messages;' 2>$null; $nativeExit=$LASTEXITCODE }
finally { $ErrorActionPreference = 'Stop' }
$value = ($count -join '').Trim()
if ($nativeExit -ne 0 -or $value -notmatch '^\d+$') { throw 'Could not count messages for the reboot baseline.' }
$state = [ordered]@{
    windows_boot_time_before=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('o')
    windows_expected_min_messages=[long]$value
    windows_reboot_recovery='pending: save work, reboot, then log in without manually starting services'
    updated_at=(Get-Date -Format o)
}
$state | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $repoRoot '.local/reboot-baseline.json') -Encoding UTF8
Write-Host 'Reboot baseline recorded. No reboot was performed.'
