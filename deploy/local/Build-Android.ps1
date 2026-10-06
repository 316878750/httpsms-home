[CmdletBinding()]
param([string[]]$Tasks = @('testDebugUnitTest', 'assembleDebug'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Use-DDriveTools.ps1') -NeedAndroid
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$gradle = if ($toolConfig -and $toolConfig.GradleHome) { Join-Path $toolConfig.GradleHome 'bin/gradle.bat' } else { Join-Path $repoRoot 'android/gradlew.bat' }
if (-not (Test-Path -LiteralPath $gradle)) { throw 'Gradle executable is missing.' }
if (-not (Test-Path (Join-Path $repoRoot 'android/app/google-services.json'))) { throw 'Import your own Firebase configuration before building.' }
Push-Location (Join-Path $repoRoot 'android')
try {
    $proxyOptions = @()
    if ($env:HTTPS_PROXY -match '^socks5h?://') {
        $javaProxy = [Uri]$env:HTTPS_PROXY
        $proxyOptions = @("-DsocksProxyHost=$($javaProxy.Host)", "-DsocksProxyPort=$($javaProxy.Port)")
    }
    # Keep Docker + Android builds within the host's limited commit/pagefile budget.
    & $gradle --no-daemon --max-workers=1 '-Dorg.gradle.jvmargs=-Xmx1280m -XX:MaxMetaspaceSize=384m -XX:ActiveProcessorCount=2 -XX:+UseSerialGC -Dfile.encoding=UTF-8' '-Pkotlin.compiler.execution.strategy=in-process' @proxyOptions @Tasks
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed; review the output above.' }
} finally {
    Pop-Location
}
