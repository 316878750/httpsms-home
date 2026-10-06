$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Use-DDriveTools.ps1')
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$ErrorActionPreference='Continue'
try { & docker compose --project-directory $repoRoot --env-file (Join-Path $repoRoot '.local/compose.env') -f (Join-Path $repoRoot 'compose.local.yml') stop; $nativeExit=$LASTEXITCODE }
finally { $ErrorActionPreference='Stop' }
if ($nativeExit -ne 0) { throw 'Could not stop the local services.' }
# Intentionally retain database, pending events and certificate volumes.
