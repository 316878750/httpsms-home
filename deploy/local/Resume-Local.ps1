[CmdletBinding()]
param([int]$TimeoutSeconds = 600, [ValidateSet('Manual','ScheduledTask')][string]$TriggerSource = 'Manual')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Use-DDriveTools.ps1')
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$statusFile = Join-Path $repoRoot '.local/startup-recovery-status.json'
$state = [ordered]@{ checked_at=(Get-Date -Format o); boot_time=$null; trigger_source=$TriggerSource; phase='starting'; success=$false; detail=$null }
function Save-State { $state.checked_at=Get-Date -Format o; $state | ConvertTo-Json | Set-Content -LiteralPath $statusFile -Encoding UTF8 }
$mutex = New-Object Threading.Mutex($false, 'Local\httpSMS-Home-Recovery')
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); exit 0 }
try {
    $state.boot_time = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('o')
    Save-State
    $config = Join-Path $repoRoot '.local/compose.env'
    $lanLine = Get-Content -LiteralPath $config | Where-Object { $_ -match '^HTTPSMS_LAN_IP=' } | Select-Object -First 1
    $lanIP = ($lanLine -split '=',2)[1].Trim()
    if (-not $lanIP) { throw 'Local LAN address is not configured.' }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $state.phase='waiting_for_home_network'; Save-State
    do {
        $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -IPAddress $lanIP -ErrorAction SilentlyContinue)
        $connected = @($addresses | Where-Object { (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue).Status -eq 'Up' }).Count -gt 0
        if ($connected) { break }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)
    if (-not $connected) { throw 'Configured home Wi-Fi address unavailable; reconnect home Wi-Fi and run Resume-Local.ps1.' }
    if (-not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path -LiteralPath $dockerDesktop)) { throw 'Configure the Docker Desktop executable using Configure-Tools.ps1.' }
        Start-Process -FilePath $dockerDesktop -WindowStyle Hidden
    }
    $state.phase='waiting_for_docker'; Save-State
    $dockerReady=$false
    do {
        $ErrorActionPreference='Continue'
        try { & docker info --format '{{.ServerVersion}}' *> $null; $nativeExit=$LASTEXITCODE }
        finally { $ErrorActionPreference='Stop' }
        if ($nativeExit -eq 0) { $dockerReady=$true; break }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)
    if (-not $dockerReady) { throw 'Docker did not become ready within the recovery window.' }
    $state.phase='restoring_services'; Save-State
    # Windows PowerShell treats Docker's normal stderr progress as errors under Stop.
    $ErrorActionPreference='Continue'
    try { & docker compose --project-directory $repoRoot --env-file $config -f (Join-Path $repoRoot 'compose.local.yml') up -d --no-build --pull never --wait --wait-timeout 120 *> $null; $nativeExit=$LASTEXITCODE }
    finally { $ErrorActionPreference='Stop' }
    if ($nativeExit -ne 0) { throw 'Local containers did not become healthy.' }
    $state.phase='checking_https'; Save-State
    # Local CA has no revocation endpoint; chain and hostname checks remain enabled.
    $ErrorActionPreference='Continue'
    try { $code = & curl.exe --noproxy '*' --ssl-revoke-best-effort --max-time 15 -s -o NUL -w '%{http_code}' https://localhost:8443/; $nativeExit=$LASTEXITCODE }
    finally { $ErrorActionPreference='Stop' }
    if ($nativeExit -ne 0 -or $code -ne '200') { throw 'Local web HTTPS trust/availability check failed.' }
    # Only mark OS reboot acceptance after an actual later boot and retained test data.
    $reportPath = Join-Path $repoRoot '.local/reboot-baseline.json'
    if (Test-Path -LiteralPath $reportPath) {
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        if ($report.windows_boot_time_before -and $null -ne $report.windows_expected_min_messages -and
            (([DateTimeOffset]$state.boot_time - [DateTimeOffset]$report.windows_boot_time_before).TotalSeconds -gt 60)) {
            $ErrorActionPreference='Continue'
            try { $counts = & docker compose --project-directory $repoRoot --env-file $config -f (Join-Path $repoRoot 'compose.local.yml') exec -T postgres psql -U httpsms -d httpsms -Atc 'SELECT count(*) FROM messages;' 2>$null; $nativeExit=$LASTEXITCODE }
            finally { $ErrorActionPreference='Stop' }
            if ($nativeExit -ne 0) { throw 'Post-reboot database check failed.' }
            $total = ($counts -join '').Trim()
            if ($total -notmatch '^\d+$' -or [long]$total -lt [long]$report.windows_expected_min_messages) { throw 'Post-reboot message retention check failed.' }
            if ($TriggerSource -eq 'ScheduledTask') {
                $report.windows_reboot_recovery='passed: actual Windows reboot; scheduled login task restored containers; HTTPS 200; message count retained'
            } else {
                $report.windows_reboot_recovery='manual recovery verified after OS reboot; automatic login recovery still pending'
            }
            $report.updated_at=Get-Date -Format o
            $report | Add-Member -NotePropertyName windows_boot_time_after -NotePropertyValue $state.boot_time -Force
            $report | ConvertTo-Json | Set-Content -LiteralPath $reportPath -Encoding UTF8
        }
    }
    $state.success=$true; $state.phase='ready'; $state.detail='Home services healthy; HTTPS verified; no images downloaded or rebuilt.'
} catch {
    $state.phase='failed'; $state.detail=$_.Exception.Message
} finally {
    Save-State
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
if (-not $state.success) { exit 1 }
