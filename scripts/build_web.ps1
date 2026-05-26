# Build Flutter web for Firebase Hosting (avoids Firebase Pigeon channel-error on web).
# Default build = testing stack (DAAO Tests + test Railway). See docs/ENVIRONMENTS.md.
# --no-tree-shake-icons: release web otherwise may omit Material icon glyphs → blank icons.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
. (Join-Path $PSScriptRoot "deepseek_define.ps1")

$defines = @(Get-DeepseekDartDefineArgs)
if ($defines.Length -eq 0) {
    Write-Warning "No DeepSeek key (secrets\deepseek_api_key.txt). AI assistant will be disabled in this build."
} else {
    Write-Host "Embedding DeepSeek key from secrets\deepseek_api_key.txt (testing build only)."
}

flutter build web --release --no-wasm-dry-run --no-tree-shake-icons --pwa-strategy=none @defines
Write-Host "Done. Deploy test site: firebase deploy --only hosting:testing"
Write-Host "For production: add --dart-define=DEPLOY_ENV=production to flutter build, then: firebase deploy --only hosting:production"
