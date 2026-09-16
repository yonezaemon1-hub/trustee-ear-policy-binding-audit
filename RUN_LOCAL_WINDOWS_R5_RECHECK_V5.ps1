param(
    [string]$Checkout = 'C:\c\no16_r5_recheck\trustee'
)

$ErrorActionPreference = 'Stop'

# V5 fixes one V4-only wrapper bug. V4 correctly found the exact Spectre-capable
# MSVC toolset, but then tried to verify VCToolsVersion with %VAR% on the same
# cmd.exe line that calls VsDevCmd.bat. cmd expands %VAR% before VsDevCmd sets it.
# The exact where-cl path check is already the stronger verification, so the
# redundant environment-variable check is removed and nothing else is changed.
$BaseCommit = '92b054523e62fdc1169549275772b74b12e72687'
$BaseUrl = "https://raw.githubusercontent.com/yonezaemon1-hub/trustee-ear-policy-binding-audit/$BaseCommit/RUN_LOCAL_WINDOWS_R5_RECHECK_V4.ps1"
$TempRunner = Join-Path $env:TEMP 'RUN_LOCAL_WINDOWS_R5_RECHECK_V5_EFFECTIVE.ps1'

$oldBlock = @'
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
'@

$newBlock = @'
$clPathFile = Join-Path $Evidence 'cl_path.txt'
$clCmdLine = "call `"$vsDevCmd`" -arch=x64 -host_arch=x64 -vcvars_ver=$VcVarsVer >nul && where cl > `"$clPathFile`" 2>&1"
& $env:ComSpec /d /c $clCmdLine
$clStatus = $LASTEXITCODE
if ($clStatus -ne 0) { throw "MSVC Spectre toolset activation failed: $clStatus" }

$resolvedCl = (Get-Content $clPathFile | Select-Object -First 1).Trim()
if (-not $resolvedCl -or -not (Test-Path $resolvedCl)) { throw "cl.exe path not resolved: $resolvedCl" }
if ([System.IO.Path]::GetFullPath($resolvedCl).TrimEnd('\') -ine [System.IO.Path]::GetFullPath($selectedCl).TrimEnd('\')) {
    throw "VsDevCmd cl.exe mismatch: resolved=$resolvedCl expected=$selectedCl"
}
'@

Write-Host '[V5] Fetching immutable V4 runner...'
$baseText = (Invoke-WebRequest -UseBasicParsing -Uri $BaseUrl).Content
if (-not $baseText.Contains($oldBlock)) {
    throw 'V5 expected V4 verification block not found in pinned V4 runner'
}

$effective = $baseText.Replace($oldBlock, $newBlock)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($TempRunner, $effective, $utf8NoBom)

Write-Host '[V5] Removed redundant pre-expansion check; executing effective runner...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $TempRunner -Checkout $Checkout
$code = $LASTEXITCODE
if ($code -ne 0) { throw "V5 effective runner failed with exit code $code" }
Write-Host 'NO16_LOCAL_WINDOWS_R5_V5_WRAPPER_PASS'
