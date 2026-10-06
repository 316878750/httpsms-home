[CmdletBinding()]
param([ValidateRange(1,2147483647)][int]$VersionCode = 2, [string]$OldDebugKeystore)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Use-DDriveTools.ps1') -NeedAndroid
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$signingDir = Join-Path $repoRoot '.local/signing'
$outDir = Join-Path $repoRoot 'releases'
if (-not (Test-Path (Join-Path $repoRoot '.local/compose.env'))) { throw 'Run Prepare-Local.ps1 first to protect the signing directory.' }
New-Item -ItemType Directory -Force -Path $signingDir,$outDir | Out-Null
# .local is already restricted to the current user and SYSTEM by Prepare-Local.ps1.
$store = Join-Path $signingDir 'httpsms-home.p12'
$passwordFile = Join-Path $signingDir 'keystore-password.txt'
$lineage = Join-Path $signingDir 'debug-to-home.lineage'
$apksigner = Join-Path $env:ANDROID_HOME 'build-tools/37.0.0/apksigner.bat'
try {
    if (-not (Test-Path -LiteralPath $store)) {
        if (Test-Path -LiteralPath $passwordFile) { throw 'Partial signing setup exists; inspect before generating another key.' }
        $bytes = New-Object byte[] 32
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
        $rng.Dispose()
        [IO.File]::WriteAllText($passwordFile, [Convert]::ToBase64String($bytes))
        $env:HTTPSMS_RELEASE_STORE_PASS = [IO.File]::ReadAllText($passwordFile).Trim()
        & keytool -genkeypair -keystore $store -storetype PKCS12 -alias httpsms-home -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=httpSMS Home Release' -storepass:env HTTPSMS_RELEASE_STORE_PASS -keypass:env HTTPSMS_RELEASE_STORE_PASS
        if ($LASTEXITCODE -ne 0) { throw 'Release key creation failed.' }
    }
    $env:HTTPSMS_RELEASE_STORE_PASS = [IO.File]::ReadAllText($passwordFile).Trim()
    if ($OldDebugKeystore -and -not (Test-Path -LiteralPath $lineage)) {
        if (-not (Test-Path -LiteralPath $OldDebugKeystore)) { throw 'Old debug keystore does not exist.' }
        # V3 key rotation preserves existing app data while replacing the debug key.
        & $apksigner rotate --out $lineage --old-signer --ks $OldDebugKeystore --ks-key-alias androiddebugkey --ks-pass pass:android --set-installed-data true --set-shared-uid false --set-permission true --set-rollback false --set-auth false --new-signer --ks $store --ks-key-alias httpsms-home --ks-pass env:HTTPSMS_RELEASE_STORE_PASS
        if ($LASTEXITCODE -ne 0) { throw 'Signing lineage creation failed.' }
    }
    & (Join-Path $PSScriptRoot 'Build-Android.ps1') -Tasks @('assembleRelease',"-PlocalVersionCode=$VersionCode")
    $unsigned = Join-Path $repoRoot 'android/app/build/outputs/apk/release/app-release-unsigned.apk'
    $output = Join-Path $outDir "httpsms-home-release-v$VersionCode.apk"
    $rotationOptions = @()
    if (Test-Path -LiteralPath $lineage) { $rotationOptions = @('--lineage',$lineage,'--rotation-min-sdk-version','28') }
    & $apksigner sign --ks $store --ks-key-alias httpsms-home --ks-pass env:HTTPSMS_RELEASE_STORE_PASS @rotationOptions --min-sdk-version 28 --v1-signing-enabled false --v2-signing-enabled false --v3-signing-enabled true --v4-signing-enabled false --debuggable-apk-permitted false --out $output $unsigned
    if ($LASTEXITCODE -ne 0) { throw 'Release signing failed.' }
    & $apksigner verify --verbose --print-certs --min-sdk-version 28 $output
    if ($LASTEXITCODE -ne 0) { throw 'Release signature verification failed.' }
    $hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    [IO.File]::WriteAllText("$output.sha256", "$hash  $([IO.Path]::GetFileName($output))`n")
    Write-Output "Verified release: $output"
} finally {
    Remove-Item Env:\HTTPSMS_RELEASE_STORE_PASS -ErrorAction SilentlyContinue
}
