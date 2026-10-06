# Historical filename retained for compatibility; every location is configurable.
param([switch]$NeedAndroid)
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$toolConfigPath = Join-Path $repoRoot '.local/tools.json'
$toolConfig = if (Test-Path -LiteralPath $toolConfigPath) { Get-Content -LiteralPath $toolConfigPath -Raw | ConvertFrom-Json } else { $null }
$toolsRoot = if ($toolConfig -and $toolConfig.CacheRoot) { $toolConfig.CacheRoot } else { Join-Path $repoRoot '.tools' }
$dockerDesktop = if ($toolConfig -and $toolConfig.DockerDesktopPath) { $toolConfig.DockerDesktopPath } else { Join-Path $env:ProgramFiles 'Docker/Docker/Docker Desktop.exe' }
if (Test-Path -LiteralPath $dockerDesktop) { $env:PATH = (Join-Path (Split-Path $dockerDesktop) 'resources/bin') + ';' + $env:PATH }
if ($NeedAndroid) {
    if ($toolConfig -and $toolConfig.JdkHome) { $env:JAVA_HOME = $toolConfig.JdkHome }
    if ($toolConfig -and $toolConfig.AndroidSdk) { $env:ANDROID_HOME = $toolConfig.AndroidSdk }
    if (-not $env:JAVA_HOME -or -not (Test-Path (Join-Path $env:JAVA_HOME 'bin/java.exe'))) { throw 'Configure a JDK using Configure-Tools.ps1 or JAVA_HOME.' }
    if (-not $env:ANDROID_HOME -or -not (Test-Path (Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe'))) { throw 'Configure Android SDK using Configure-Tools.ps1 or ANDROID_HOME.' }
    $env:ANDROID_USER_HOME = Join-Path $toolsRoot 'android-user'
    $env:ANDROID_AVD_HOME = Join-Path $toolsRoot 'android-user/avd'
    $env:GRADLE_USER_HOME = Join-Path $toolsRoot 'gradle'
    $env:TEMP = Join-Path $toolsRoot 'temp'
    $env:TMP = $env:TEMP
    $env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\cmdline-tools\latest\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"
    foreach ($dir in @($env:ANDROID_USER_HOME, $env:ANDROID_AVD_HOME, $env:GRADLE_USER_HOME, $env:TEMP)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
}
