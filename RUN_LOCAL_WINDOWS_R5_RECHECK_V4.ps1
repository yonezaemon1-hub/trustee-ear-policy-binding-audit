param(
    [string]$Checkout = 'C:\c\no16_r5_recheck\trustee'
)

$ErrorActionPreference = 'Stop'

# V4 wraps the immutable V2 runner and applies only environment/audit fixes:
# 1) use a fresh short target dir so the failed 14.50 partial build is not reused;
# 2) search ALL Visual Studio installs for an MSVC toolset that actually contains
#    lib\spectre\x64, then select the highest such toolset;
# 3) force that same toolset in both the verification step and Cargo step;
# 4) read the clean-before file with utf-8-sig so a PowerShell 5.1 BOM is not
#    misclassified as a dirty checkout.
$BaseCommit = '6be9b7936cf3d32dd502c9e7e779736d44bcfb55'
$BaseUrl = "https://raw.githubusercontent.com/yonezaemon1-hub/trustee-ear-policy-binding-audit/$BaseCommit/RUN_LOCAL_WINDOWS_R5_RECHECK_V2.ps1"
$TempRunner = Join-Path $env:TEMP 'RUN_LOCAL_WINDOWS_R5_RECHECK_V4_EFFECTIVE.ps1'

$oldTarget = '$CargoTarget = ''C:\n16o'''
$newTarget = '$CargoTarget = ''C:\n16o51'''

$oldMsvcBlock = @'
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

$newMsvcBlock = @'
Write-Host '[4/7] Verifying Spectre-capable MSVC x64 build environment...'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found' }

$vsInstalls = @(
    & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)
if ($vsInstalls.Count -eq 0) { throw 'No Visual Studio installation with C++ x64/x86 tools was found' }
$vsInstalls | Set-Content -Path (Join-Path $Evidence 'vs_installations_all.txt') -Encoding UTF8

$candidates = @()
foreach ($install in $vsInstalls) {
    $root = Join-Path $install 'VC\Tools\MSVC'
    if (-not (Test-Path $root)) { continue }
    foreach ($dir in @(Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue)) {
        $cl = Join-Path $dir.FullName 'bin\Hostx64\x64\cl.exe'
        $spectre = Join-Path $dir.FullName 'lib\spectre\x64'
        $libCount = 0
        if (Test-Path $spectre) {
            $libCount = @(Get-ChildItem -Path $spectre -Filter '*.lib' -File -ErrorAction SilentlyContinue).Count
        }
        if ((Test-Path $cl) -and $libCount -gt 0) {
            try { $ver = [version]$dir.Name } catch { continue }
            $candidates += [pscustomobject]@{
                Version = $ver
                VersionText = $dir.Name
                VsInstall = $install
                ToolsetDir = $dir.FullName
                Cl = $cl
                Spectre = $spectre
                SpectreLibCount = $libCount
            }
        }
    }
}

if ($candidates.Count -eq 0) {
    throw 'No installed MSVC toolset with x64 Spectre-mitigated libraries was found in any Visual Studio installation'
}

$candidates |
    Sort-Object Version -Descending |
    ForEach-Object { "$($_.VersionText)`t$($_.VsInstall)`t$($_.Spectre)`tlibs=$($_.SpectreLibCount)" } |
    Set-Content -Path (Join-Path $Evidence 'msvc_spectre_candidates.txt') -Encoding UTF8

$selected = $candidates | Sort-Object Version -Descending | Select-Object -First 1
$vsInstall = $selected.VsInstall
$vsDevCmd = Join-Path $vsInstall 'Common7\Tools\VsDevCmd.bat'
if (-not (Test-Path $vsDevCmd)) { throw "VsDevCmd.bat not found: $vsDevCmd" }
$VcToolsVersion = $selected.VersionText
$verParts = $VcToolsVersion.Split('.')
if ($verParts.Count -lt 2) { throw "unexpected VCTools version: $VcToolsVersion" }
$VcVarsVer = "$($verParts[0]).$($verParts[1])"
$selectedCl = $selected.Cl
$spectreLib = $selected.Spectre
$spectreLibCount = $selected.SpectreLibCount

$clPathFile = Join-Path $Evidence 'cl_path.txt'
$vctoolsFile = Join-Path $Evidence 'vctools_env.txt'
$clCmdLine = "call `"$vsDevCmd`" -arch=x64 -host_arch=x64 -vcvars_ver=$VcVarsVer >nul && where cl > `"$clPathFile`" 2>&1 && echo %VCToolsVersion% > `"$vctoolsFile`""
& $env:ComSpec /d /c $clCmdLine
$clStatus = $LASTEXITCODE
if ($clStatus -ne 0) { throw "MSVC Spectre toolset activation failed: $clStatus" }

$resolvedCl = (Get-Content $clPathFile | Select-Object -First 1).Trim()
if (-not $resolvedCl -or -not (Test-Path $resolvedCl)) { throw "cl.exe path not resolved: $resolvedCl" }
$resolvedVersion = (Get-Content $vctoolsFile -Raw).Trim().TrimEnd('\')
if ($resolvedVersion -ne $VcToolsVersion) {
    throw "VsDevCmd selected VCToolsVersion $resolvedVersion, expected $VcToolsVersion"
}
if ([System.IO.Path]::GetFullPath($resolvedCl).TrimEnd('\') -ine [System.IO.Path]::GetFullPath($selectedCl).TrimEnd('\')) {
    throw "VsDevCmd cl.exe mismatch: resolved=$resolvedCl expected=$selectedCl"
}

$clInfo = (Get-Item $resolvedCl).VersionInfo
@(
    "vs_install=$vsInstall"
    "vsdevcmd=$vsDevCmd"
    "vctools_version=$VcToolsVersion"
    "vcvars_ver=$VcVarsVer"
    "spectre_lib_dir=$spectreLib"
    "spectre_lib_count=$spectreLibCount"
    'spectre_lib_exists=true'
) | Set-Content -Path (Join-Path $Evidence 'msvc_environment.txt') -Encoding UTF8
@(
    "path=$resolvedCl"
    "file_version=$($clInfo.FileVersion)"
    "product_version=$($clInfo.ProductVersion)"
) | Set-Content -Path (Join-Path $Evidence 'cl_version.txt') -Encoding UTF8
Write-Host "selected_vctools_version=$VcToolsVersion"
Write-Host "selected_vs_install=$vsInstall"
Write-Host "spectre_lib_dir=$spectreLib"
Write-Host "spectre_lib_count=$spectreLibCount"
'@

$oldCargoLine = '$cmdLine = "call `"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && set `"PATH=$protocBin;%PATH%`" && set `"CARGO_TARGET_DIR=$CargoTarget`" && set `"CARGO_NET_GIT_FETCH_WITH_CLI=true`" && cd /d `"$Checkout`" && $command > `"$log`" 2>&1"'
$newCargoLine = '$cmdLine = "call `"$vsDevCmd`" -arch=x64 -host_arch=x64 -vcvars_ver=$VcVarsVer >nul && set `"PATH=$protocBin;%PATH%`" && set `"CARGO_TARGET_DIR=$CargoTarget`" && set `"CARGO_NET_GIT_FETCH_WITH_CLI=true`" && cd /d `"$Checkout`" && $command > `"$log`" 2>&1"'

$oldBeforeRead = "before = (e / 'git_status_before.txt').read_text(encoding='utf-8', errors='replace')"
$newBeforeRead = "before = (e / 'git_status_before.txt').read_text(encoding='utf-8-sig', errors='replace')"

Write-Host '[V4] Fetching immutable V2 base runner...'
$baseText = (Invoke-WebRequest -UseBasicParsing -Uri $BaseUrl).Content
foreach ($required in @($oldTarget, $oldMsvcBlock, $oldCargoLine, $oldBeforeRead)) {
    if (-not $baseText.Contains($required)) {
        throw 'V4 expected patch anchor not found in pinned V2 base runner'
    }
}

$effective = $baseText.Replace($oldTarget, $newTarget)
$effective = $effective.Replace($oldMsvcBlock, $newMsvcBlock)
$effective = $effective.Replace($oldCargoLine, $newCargoLine)
$effective = $effective.Replace($oldBeforeRead, $newBeforeRead)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($TempRunner, $effective, $utf8NoBom)

Write-Host '[V4] Spectre-aware MSVC selection patched; executing effective runner...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $TempRunner -Checkout $Checkout
$code = $LASTEXITCODE
if ($code -ne 0) { throw "V4 effective runner failed with exit code $code" }
Write-Host 'NO16_LOCAL_WINDOWS_R5_V4_WRAPPER_PASS'
