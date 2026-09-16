param(
    [string]$Checkout = 'C:\c\no16_r5_recheck\trustee'
)

$ErrorActionPreference = 'Stop'

$FixedCommit = '512fed65642015b849f38fb13bfdec7806639987'
$RustToolchain = '1.95.0'
$TestName = 'test_native_inert_revision_binding'
$ExpectedSnippetSha256 = '1e69a6d7d3eaede9bcd9082ea0a01fd9ad01b0894a7d359c995b3416efe9662d'
$ExpectedPatchedBrokerSha256 = '0b34df6b20e90625c28555f36930b7502f5f36b08a349de219f232ea29ebad71'
$ExpectedInjectionDiffSha256 = '8e5d163d2b5eaf538aea2d73d8585100853cb3b113f316fa8176824a94cdf502'
$ExpectedProtocArchiveSha256 = '70381b116ab0d71cb6a5177d9b17c7c13415866603a0fd40d513dafe32d56c35'
$SnippetCommit = '19c83ccd3208530df93e863c20e9c0f5ee2b6c78'
$SnippetUrl = "https://raw.githubusercontent.com/yonezaemon1-hub/trustee-ear-policy-binding-audit/$SnippetCommit/test_snippet.rs"
$ProtocUrl = 'https://github.com/protocolbuffers/protobuf/releases/download/v31.1/protoc-31.1-win64.zip'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Evidence = Join-Path $env:TEMP "NO16_LOCAL_WINDOWS_R5_RECHECK_$stamp"
$CargoTarget = 'C:\n16o'
$ProtocRoot = Join-Path $env:TEMP "n16p_$stamp"
$ProtocZip = Join-Path $env:TEMP "n16p_$stamp.zip"
$DefaultCargoHome = Join-Path $env:USERPROFILE '.cargo'
$DefaultRustupHome = Join-Path $env:USERPROFILE '.rustup'
$DefaultCargoBin = Join-Path $DefaultCargoHome 'bin'
$RustupExe = Join-Path $DefaultCargoBin 'rustup.exe'
$RustcExe = Join-Path $DefaultCargoBin 'rustc.exe'
$CargoExe = Join-Path $DefaultCargoBin 'cargo.exe'

New-Item -ItemType Directory -Force -Path $Evidence | Out-Null
if (Test-Path $CargoTarget) { Remove-Item -Recurse -Force $CargoTarget }
New-Item -ItemType Directory -Force -Path $CargoTarget | Out-Null

# Important: local recheck must use the user's existing rustup/cargo installation.
# The previous runner incorrectly redirected CARGO_HOME to C:\n16c.
$InheritedCargoHome = $env:CARGO_HOME
if (Test-Path Env:CARGO_HOME) {
    Remove-Item Env:CARGO_HOME
}
$env:CARGO_TARGET_DIR = $CargoTarget
$env:CARGO_NET_GIT_FETCH_WITH_CLI = 'true'
$env:CARGO_TERM_COLOR = 'never'
if ($env:PATH -notlike "$DefaultCargoBin*") {
    $env:PATH = "$DefaultCargoBin;$env:PATH"
}

if (-not (Test-Path $RustupExe)) { throw "rustup.exe not found at expected user install: $RustupExe" }
if (-not (Test-Path $RustcExe)) { throw "rustc.exe not found at expected user install: $RustcExe" }
if (-not (Test-Path $CargoExe)) { throw "cargo.exe not found at expected user install: $CargoExe" }
if (-not (Test-Path $DefaultRustupHome)) { throw "rustup home not found: $DefaultRustupHome" }

git config --global core.longpaths true
if ($LASTEXITCODE -ne 0) { throw 'failed to enable git core.longpaths' }

if (-not (Test-Path (Join-Path $Checkout '.git'))) {
    throw "Trustee checkout not found: $Checkout"
}

git -C $Checkout config core.autocrlf false
$head = (git -C $Checkout rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'git rev-parse failed' }
if ($head -ne $FixedCommit) { throw "wrong Trustee HEAD: $head" }

$before = @(git -C $Checkout status --short)
'' | Set-Content -Path (Join-Path $Evidence 'git_status_before.txt') -Encoding UTF8
if ($before.Count -ne 0) {
    $before | Set-Content -Path (Join-Path $Evidence 'git_status_before.txt') -Encoding UTF8
    throw "checkout is not clean before injection: $($before -join '; ')"
}

@(
    "head=$head"
    "fixed_commit=$FixedCommit"
    'match=true'
) | Set-Content -Path (Join-Path $Evidence 'commit.txt') -Encoding ASCII

@(
    "computer_name=$env:COMPUTERNAME"
    "os_version=$([Environment]::OSVersion.VersionString)"
    "powershell=$($PSVersionTable.PSVersion)"
    "checkout=$Checkout"
    "inherited_cargo_home=$InheritedCargoHome"
    "effective_cargo_home=<unset; rustup default user home>"
    "default_cargo_home=$DefaultCargoHome"
    "default_rustup_home=$DefaultRustupHome"
    "cargo_target_dir=$CargoTarget"
    "evidence=$Evidence"
) | Set-Content -Path (Join-Path $Evidence 'environment.txt') -Encoding UTF8
try {
    $os = Get-CimInstance Win32_OperatingSystem
    "os_caption=$($os.Caption)" | Add-Content -Path (Join-Path $Evidence 'environment.txt') -Encoding UTF8
    "os_build=$($os.BuildNumber)" | Add-Content -Path (Join-Path $Evidence 'environment.txt') -Encoding UTF8
} catch {}
cmd.exe /c ver 2>&1 | Add-Content -Path (Join-Path $Evidence 'environment.txt') -Encoding UTF8

git --version 2>&1 | Set-Content -Path (Join-Path $Evidence 'git_version.txt') -Encoding UTF8
python --version 2>&1 | Set-Content -Path (Join-Path $Evidence 'python_version.txt') -Encoding UTF8

Write-Host '[1/7] Downloading exact R5 witness bytes...'
$snippet = Join-Path $Evidence 'test_snippet.rs'
Invoke-WebRequest -Uri $SnippetUrl -OutFile $snippet
$snippetHash = (Get-FileHash $snippet -Algorithm SHA256).Hash.ToLowerInvariant()
"$snippetHash  test_snippet.rs" | Set-Content -Path (Join-Path $Evidence 'test_snippet_sha256.txt') -Encoding ASCII
if ($snippetHash -ne $ExpectedSnippetSha256) { throw "R5 snippet SHA-256 mismatch: $snippetHash" }

Write-Host '[2/7] Installing/verifying pinned protoc 31.1...'
Invoke-WebRequest -Uri $ProtocUrl -OutFile $ProtocZip
$protocArchiveHash = (Get-FileHash $ProtocZip -Algorithm SHA256).Hash.ToLowerInvariant()
@(
    "url=$ProtocUrl"
    "sha256=$protocArchiveHash"
    "expected_sha256=$ExpectedProtocArchiveSha256"
) | Set-Content -Path (Join-Path $Evidence 'protoc_source.txt') -Encoding ASCII
if ($protocArchiveHash -ne $ExpectedProtocArchiveSha256) { throw "protoc ZIP SHA-256 mismatch: $protocArchiveHash" }
Expand-Archive -Path $ProtocZip -DestinationPath $ProtocRoot -Force
$protocBin = Join-Path $ProtocRoot 'bin'
$protocExe = Join-Path $protocBin 'protoc.exe'
$env:PATH = "$protocBin;$env:PATH"
$protocVersion = (& $protocExe --version 2>&1 | Out-String).Trim()
$protocVersion | Set-Content -Path (Join-Path $Evidence 'protoc_version.txt') -Encoding ASCII
if ($protocVersion -ne 'libprotoc 31.1') { throw "unexpected protoc version: $protocVersion" }

Write-Host '[3/7] Verifying existing Rust 1.95.0 toolchain...'
& $RustupExe show 2>&1 | Set-Content -Path (Join-Path $Evidence 'rustup_show.txt') -Encoding UTF8
$rustupStatus = $LASTEXITCODE
if ($rustupStatus -ne 0) { throw "rustup show failed: $rustupStatus" }
& $RustcExe "+$RustToolchain" --version 2>&1 | Set-Content -Path (Join-Path $Evidence 'rustc_version.txt') -Encoding UTF8
$rustcStatus = $LASTEXITCODE
if ($rustcStatus -ne 0) { throw "rustc +$RustToolchain failed: $rustcStatus" }
& $CargoExe "+$RustToolchain" --version 2>&1 | Set-Content -Path (Join-Path $Evidence 'cargo_version.txt') -Encoding UTF8
$cargoVersionStatus = $LASTEXITCODE
if ($cargoVersionStatus -ne 0) { throw "cargo +$RustToolchain failed: $cargoVersionStatus" }
$rustc = (Get-Content (Join-Path $Evidence 'rustc_version.txt') -Raw).Trim()
$cargo = (Get-Content (Join-Path $Evidence 'cargo_version.txt') -Raw).Trim()
if ($rustc -notmatch '^rustc 1\.95\.0 ') { throw "wrong rustc: $rustc" }
if ($cargo -notmatch '^cargo 1\.95\.0 ') { throw "wrong cargo: $cargo" }

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

Write-Host '[5/7] Injecting byte-identical R5 witness...'
$env:NO16_CHECKOUT = $Checkout
$env:NO16_EVIDENCE = $Evidence
$env:NO16_TEST_NAME = $TestName
@'
from pathlib import Path
import os, re, subprocess
checkout = Path(os.environ['NO16_CHECKOUT'])
evidence = Path(os.environ['NO16_EVIDENCE'])
broker = checkout / 'attestation-service/src/ear_token/broker.rs'
snippet = evidence / 'test_snippet.rs'
source = broker.read_text(encoding='utf-8')
test_name = os.environ['NO16_TEST_NAME']
if f'fn {test_name}' in source:
    raise SystemExit('test already present before injection')
if not re.search(r'(?s)#\[cfg\(test\)\]\s*mod tests\s*\{.*\}\s*$', source):
    raise SystemExit('could not locate final tests module')
test_body = snippet.read_text(encoding='utf-8')
injected = re.sub(r'\}\s*$', '\n' + test_body + '\n}\n', source)
broker.write_text(injected, encoding='utf-8', newline='\n')
with (evidence / 'injection.diff').open('wb') as f:
    subprocess.run(['git', '-C', str(checkout), 'diff', '--', 'attestation-service/src/ear_token/broker.rs'], stdout=f, check=True)
'@ | python -
if ($LASTEXITCODE -ne 0) { throw 'R5 injection failed' }

$brokerRel = 'attestation-service/src/ear_token/broker.rs'
$broker = Join-Path $Checkout 'attestation-service\src\ear_token\broker.rs'
Copy-Item $broker (Join-Path $Evidence 'patched_broker.rs')
$after = @(git -C $Checkout status --short)
$after | Set-Content -Path (Join-Path $Evidence 'git_status_after.txt') -Encoding UTF8
if ($after.Count -ne 1 -or $after[0] -notmatch 'attestation-service/src/ear_token/broker\.rs') { throw "unexpected changed files after injection: $($after -join '; ')" }
$patchedHash = (Get-FileHash $broker -Algorithm SHA256).Hash.ToLowerInvariant()
$diffHash = (Get-FileHash (Join-Path $Evidence 'injection.diff') -Algorithm SHA256).Hash.ToLowerInvariant()
"$patchedHash  patched_broker.rs" | Set-Content -Path (Join-Path $Evidence 'patched_broker_sha256.txt') -Encoding ASCII
"$diffHash  injection.diff" | Set-Content -Path (Join-Path $Evidence 'injection_diff_sha256.txt') -Encoding ASCII
if ($patchedHash -ne $ExpectedPatchedBrokerSha256) { throw "patched broker differs from frozen R5: $patchedHash" }
if ($diffHash -ne $ExpectedInjectionDiffSha256) { throw "injection diff differs from frozen R5: $diffHash" }

Write-Host '[6/7] Running exact native R5 test...'
$command = "cargo +$RustToolchain -vv test --locked -p attestation-service --lib $TestName -- --nocapture"
$command | Set-Content -Path (Join-Path $Evidence 'cargo_command.txt') -Encoding ASCII
$log = Join-Path $Evidence 'cargo_test.log'
$cmdLine = "call `"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && set `"PATH=$protocBin;%PATH%`" && set `"CARGO_TARGET_DIR=$CargoTarget`" && set `"CARGO_NET_GIT_FETCH_WITH_CLI=true`" && cd /d `"$Checkout`" && $command > `"$log`" 2>&1"
& $env:ComSpec /d /c $cmdLine
$cargoStatus = $LASTEXITCODE
"$cargoStatus" | Set-Content -Path (Join-Path $Evidence 'exit_code.txt') -Encoding ASCII
Get-Content $log
Write-Host "cargo_exit_code=$cargoStatus"

Write-Host '[7/7] Applying publication-grade R5 evidence gate...'
$env:NO16_EXPECTED_SNIPPET_SHA256 = $ExpectedSnippetSha256
$env:NO16_EXPECTED_PATCHED_SHA256 = $ExpectedPatchedBrokerSha256
$env:NO16_EXPECTED_DIFF_SHA256 = $ExpectedInjectionDiffSha256
@'
from pathlib import Path
import json, os, re, sys

e = Path(os.environ['NO16_EVIDENCE'])
raw = (e / 'cargo_test.log').read_text(encoding='utf-8', errors='replace')
ansi = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
log = ansi.sub('', raw)
exit_code = int((e / 'exit_code.txt').read_text().strip())
commit = (e / 'commit.txt').read_text(encoding='utf-8', errors='replace')
before = (e / 'git_status_before.txt').read_text(encoding='utf-8', errors='replace')
after_lines = [x for x in (e / 'git_status_after.txt').read_text(encoding='utf-8', errors='replace').splitlines() if x.strip()]
snippet_sha = (e / 'test_snippet_sha256.txt').read_text().split()[0]
patched_sha = (e / 'patched_broker_sha256.txt').read_text().split()[0]
diff_sha = (e / 'injection_diff_sha256.txt').read_text().split()[0]
protoc_version = (e / 'protoc_version.txt').read_text().strip()
ma = re.search(r'(?m)^sha384_a=([0-9a-f]{96})\r?$', log)
mb = re.search(r'(?m)^sha384_b=([0-9a-f]{96})\r?$', log)
checks = {
    'head_matches_fixed_commit': 'match=true' in commit.lower(),
    'clean_before_injection': before.strip() == '',
    'only_broker_changed': len(after_lines) == 1 and 'attestation-service/src/ear_token/broker.rs' in after_lines[0].replace('\\', '/'),
    'exact_r5_snippet_sha256': snippet_sha == os.environ['NO16_EXPECTED_SNIPPET_SHA256'],
    'patched_broker_byte_identical_to_frozen_r5': patched_sha == os.environ['NO16_EXPECTED_PATCHED_SHA256'],
    'injection_diff_byte_identical_to_frozen_r5': diff_sha == os.environ['NO16_EXPECTED_DIFF_SHA256'],
    'protoc_31_1_exact': protoc_version == 'libprotoc 31.1',
    'cargo_exit_zero': exit_code == 0,
    'target_test_executed_and_ok': f"test ear_token::broker::tests::{os.environ['NO16_TEST_NAME']} ... ok" in log,
    'one_pass_zero_fail': re.search(r'test result: ok\. 1 passed; 0 failed;', log) is not None,
    'sha384_a_present': ma is not None,
    'sha384_b_present': mb is not None,
    'sha384_a_ne_b': ma is not None and mb is not None and ma.group(1) != mb.group(1),
    'same_logical_policy_identity': 'same_logical_policy_identity=true' in log,
    'signature_a_verified': 'signature_a_verified=true' in log,
    'signature_b_verified': 'signature_b_verified=true' in log,
    'digest_a_absent': 'digest_a_absent_from_both_signed_payloads=true' in log,
    'digest_b_absent': 'digest_b_absent_from_both_signed_payloads=true' in log,
    'explicit_policy_hash_paths_a_empty': 'observed_explicit_policy_hash_field_paths_a=[]' in log,
    'explicit_policy_hash_paths_b_empty': 'observed_explicit_policy_hash_field_paths_b=[]' in log,
    'temporal_exclusions_exact': 'temporal_exclusions=iat,exp' in log,
    'normalized_non_temporal_payload_equal': 'normalized_non_temporal_payload_equal=true' in log,
    'r5_marker': 'PASS_NATIVE_INERT_REVISION_BINDING_TEST' in log,
}
passed = all(checks.values())
(e / 'gate_checks.json').write_text(json.dumps(checks, indent=2, sort_keys=True) + '\n', encoding='utf-8')
lines = [f"{k}={str(v).lower()}" for k, v in checks.items()]
lines.append(f"final={'PASS' if passed else 'FAIL'}")
if passed:
    lines.append('NO16_LOCAL_WINDOWS_R5_PASS')
(e / 'final_result.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
print('\n'.join(lines))
sys.exit(0 if passed else 1)
'@ | python -
$gateStatus = $LASTEXITCODE

# Restore the checkout after capturing all R5 evidence.
git -C $Checkout checkout -- $brokerRel
$cleanupStatus = @(git -C $Checkout status --short)
$cleanupStatus | Set-Content -Path (Join-Path $Evidence 'git_status_cleanup.txt') -Encoding UTF8
if ($cleanupStatus.Count -ne 0) { throw "checkout cleanup failed: $($cleanupStatus -join '; ')" }

# Self-verifying evidence manifest, excluding the manifest itself.
$env:NO16_EVIDENCE = $Evidence
@'
from pathlib import Path
import hashlib, os

e = Path(os.environ['NO16_EVIDENCE'])
manifest = []
for p in sorted(x for x in e.rglob('*') if x.is_file() and x.name != 'SHA256SUMS.txt'):
    h = hashlib.sha256(p.read_bytes()).hexdigest()
    manifest.append(f"{h}  ./{p.relative_to(e).as_posix()}")
(e / 'SHA256SUMS.txt').write_text('\n'.join(manifest) + '\n', encoding='ascii')
'@ | python -
if ($LASTEXITCODE -ne 0) { throw 'failed to build SHA256SUMS.txt' }

$zipOut = Join-Path $env:USERPROFILE "Downloads\NO16_LOCAL_WINDOWS_R5_RECHECK_$stamp.zip"
if (Test-Path $zipOut) { Remove-Item -Force $zipOut }
Compress-Archive -Path (Join-Path $Evidence '*') -DestinationPath $zipOut -CompressionLevel Optimal
$zipHash = (Get-FileHash $zipOut -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "evidence_zip=$zipOut"
Write-Host "evidence_zip_sha256=$zipHash"

if ($gateStatus -ne 0) { throw "R5 evidence gate failed. Evidence retained at $Evidence and $zipOut" }
Write-Host 'NO16_LOCAL_WINDOWS_R5_PASS'
