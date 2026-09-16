param(
    [string]$Checkout = 'C:\c\no16_r5_recheck\trustee'
)

$ErrorActionPreference = 'Stop'

# V3 is a deterministic wrapper around the frozen V2 runner. It fetches V2
# from an immutable commit, replaces only the MSVC verification block, and
# executes the patched runner. This avoids Windows PowerShell treating cl.exe
# banner/help text written to stderr as a terminating NativeCommandError.
$BaseCommit = '6be9b7936cf3d32dd502c9e7e779736d44bcfb55'
$BaseUrl = "https://raw.githubusercontent.com/yonezaemon1-hub/trustee-ear-policy-binding-audit/$BaseCommit/RUN_LOCAL_WINDOWS_R5_RECHECK_V2.ps1"
$TempRunner = Join-Path $env:TEMP 'RUN_LOCAL_WINDOWS_R5_RECHECK_V3_EFFECTIVE.ps1'

$oldBlock = @'
Write-Host '[4/7] Verifying MSVC x64 build environment...'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found' }
$vsInstall = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1).Trim()
if (-not $vsInstall) { throw 'Visual Studio C++ toolchain not found' }
$vsDevCmd = Join-Path $vsInstall 'Common7\Tools\VsDevCmd.bat'
@("vs_install=$vsInstall", "vsdevcmd=$vsDevCmd") | Set-Content -Path (Join-Path $Evidence 'msvc_environment.txt') -Encoding UTF8
$clOut = & $env:ComSpec /d /c "call `"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && where cl && cl" 2>&1
$clStatus = $LASTEXITCODE
$clOut | Set-Content -Path (Join-Path $Evidence 'cl_version.txt') -Encoding UTF8
if ($clStatus -ne 0) { throw "MSVC verification failed: $clStatus" }
'@

$newBlock = @'
Write-Host '[4/7] Verifying MSVC x64 build environment...'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found' }
$vsInstall = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1).Trim()
if (-not $vsInstall) { throw 'Visual Studio C++ toolchain not found' }
$vsDevCmd = Join-Path $vsInstall 'Common7\Tools\VsDevCmd.bat'
@("vs_install=$vsInstall", "vsdevcmd=$vsDevCmd") | Set-Content -Path (Join-Path $Evidence 'msvc_environment.txt') -Encoding UTF8
$clPathFile = Join-Path $Evidence 'cl_path.txt'
$clCmdLine = "call `"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && where cl > `"$clPathFile`" 2>&1"
& $env:ComSpec /d /c $clCmdLine
$clStatus = $LASTEXITCODE
if ($clStatus -ne 0) { throw "MSVC where-cl verification failed: $clStatus" }
$clPath = (Get-Content $clPathFile | Select-Object -First 1).Trim()
if (-not $clPath -or -not (Test-Path $clPath)) { throw "cl.exe path not resolved: $clPath" }
$clInfo = (Get-Item $clPath).VersionInfo
@(
    "path=$clPath"
    "file_version=$($clInfo.FileVersion)"
    "product_version=$($clInfo.ProductVersion)"
) | Set-Content -Path (Join-Path $Evidence 'cl_version.txt') -Encoding UTF8
'@

Write-Host '[V3] Fetching immutable V2 base runner...'
$baseText = (Invoke-WebRequest -UseBasicParsing -Uri $BaseUrl).Content
if (-not $baseText.Contains($oldBlock)) {
    throw 'V3 expected MSVC block not found in pinned V2 base runner'
}
$effective = $baseText.Replace($oldBlock, $newBlock)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($TempRunner, $effective, $utf8NoBom)

Write-Host '[V3] MSVC verification patched; executing effective runner...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $TempRunner -Checkout $Checkout
$code = $LASTEXITCODE
if ($code -ne 0) { throw "V3 effective runner failed with exit code $code" }
Write-Host 'NO16_LOCAL_WINDOWS_R5_V3_WRAPPER_PASS'