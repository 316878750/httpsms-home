[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$JdkHome,
    [Parameter(Mandatory)][string]$AndroidSdk,
    [Parameter(Mandatory)][string]$CacheRoot,
    [string]$DockerDesktopPath,
    [string]$GradleHome
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not (Test-Path (Join-Path $repoRoot '.local/compose.env'))) { throw 'Run Prepare-Local.ps1 first.' }
if (-not (Test-Path (Join-Path $JdkHome 'bin/java.exe'))) { throw 'JdkHome must contain bin/java.exe.' }
if (-not (Test-Path (Join-Path $AndroidSdk 'platform-tools/adb.exe'))) { throw 'Install Android platform-tools first.' }
if ($DockerDesktopPath -and -not (Test-Path -LiteralPath $DockerDesktopPath)) { throw 'DockerDesktopPath does not exist.' }
if ($GradleHome -and -not (Test-Path (Join-Path $GradleHome 'bin/gradle.bat'))) { throw 'GradleHome must contain bin/gradle.bat.' }
$config = [ordered]@{
    JdkHome=[IO.Path]::GetFullPath($JdkHome)
    AndroidSdk=[IO.Path]::GetFullPath($AndroidSdk)
    CacheRoot=[IO.Path]::GetFullPath($CacheRoot)
    DockerDesktopPath=$DockerDesktopPath
    GradleHome=$GradleHome
}
[IO.File]::WriteAllText((Join-Path $repoRoot '.local/tools.json'), ($config | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host 'Local tool locations saved. No machine paths were added to tracked files.'
