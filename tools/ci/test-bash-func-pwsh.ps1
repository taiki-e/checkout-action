# SPDX-License-Identifier: Apache-2.0 OR MIT

# Test script used by tools/ci/test-bash-func.sh.

Set-StrictMode -Version Latest

$prev_err_action = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& bash -c "/usr/bin/env | grep -F '=() {'"
$code = $LASTEXITCODE
$ErrorActionPreference = "$prev_err_action"
if ($code -ne 0) { exit 1 }

# NB: Sync with action.yml
(Get-ChildItem Env:*) | ForEach-Object {
  # -LiteralPath is important since BASH_FUNC_[%% is valid environment variable to override [.
  if ($_.Value.StartsWith("() {")) { Remove-Item -LiteralPath "Env:\$($_.Key)" }
}

$prev_err_action = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& bash -c "/usr/bin/env | grep -F '=() {'"
$code = $LASTEXITCODE
$ErrorActionPreference = "$prev_err_action"
if ($code -ne 1) { exit 1 }
