[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WebConfig,
    [Parameter(Mandatory)][string]$AndroidConfig,
    [Parameter(Mandatory)][string]$ServiceAccount
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$localDir = Join-Path $repoRoot '.local'
if (-not (Test-Path (Join-Path $localDir 'compose.env'))) { throw 'Run Prepare-Local.ps1 first.' }
$web = Get-Content -LiteralPath $WebConfig -Raw | ConvertFrom-Json
$android = Get-Content -LiteralPath $AndroidConfig -Raw | ConvertFrom-Json
$service = Get-Content -LiteralPath $ServiceAccount -Raw | ConvertFrom-Json
if (-not $web.projectId -or $web.projectId -eq 'CHANGE_ME') { throw 'Fill the Web config with your own project.' }
if ($web.projectId -ne $android.project_info.project_id -or $web.projectId -ne $service.project_id) { throw 'All three Firebase configs must use the same project.' }
if ($service.type -ne 'service_account' -or -not $service.private_key) { throw 'Backend input is not a service account.' }
if (-not (@($android.client) | Where-Object { $_.client_info.android_client_info.package_name -eq 'com.httpsms' })) { throw 'Register an Android app with package com.httpsms.' }
foreach ($field in @('apiKey','authDomain','appId','messagingSenderId')) {
    if (-not $web.$field -or $web.$field -eq 'CHANGE_ME') { throw "Missing Web config field: $field" }
}
if ($web.messagingSenderId -ne [string]$android.project_info.project_number) { throw 'Firebase sender ID mismatch.' }
function Set-EnvValues([string]$Path, [hashtable]$Values) {
    $lines = @(Get-Content -LiteralPath $Path)
    foreach ($key in $Values.Keys) {
        $value = [string]$Values[$key]
        if ($value.Contains("'") -or $value.Contains("`r") -or $value.Contains("`n")) { throw 'Unsupported characters in a configuration value.' }
        $found = $false
        $lines = @($lines | ForEach-Object {
            if ($_ -match ('^' + [regex]::Escape($key) + '=')) { $found = $true; "$key='$value'" } else { $_ }
        })
        if (-not $found) { $lines += "$key='$value'" }
    }
    [IO.File]::WriteAllText($Path, ($lines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
}
Set-EnvValues (Join-Path $localDir 'compose.env') @{
    FIREBASE_API_KEY=$web.apiKey; FIREBASE_AUTH_DOMAIN=$web.authDomain
    FIREBASE_PROJECT_ID=$web.projectId; FIREBASE_APP_ID=$web.appId
    FIREBASE_MESSAGING_SENDER_ID=$web.messagingSenderId
}
Set-EnvValues (Join-Path $localDir 'api.env') @{
    GCP_PROJECT_ID=$web.projectId
    FIREBASE_CREDENTIALS=($service | ConvertTo-Json -Depth 30 -Compress)
}
Copy-Item -LiteralPath $AndroidConfig -Destination (Join-Path $repoRoot 'android/app/google-services.json') -Force
Write-Host 'Own-project Firebase configuration imported. Credentials were not printed.'
