# Reliable "flutter run -d chrome" when build\flutter_assets is locked (Chrome + OneDrive).
# Also passes DEEPSEEK_API_KEY from secrets\deepseek_api_key.txt when present.
# Closes ALL Chrome windows, removes build/.dart_tool, then runs.
param(
    [switch]$SkipKillChrome,
    [switch]$SkipClean
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
. (Join-Path $PSScriptRoot "deepseek_define.ps1")

if (-not $SkipKillChrome) {
    Write-Host "Closing Chrome (avoids locks on build\flutter_assets)..."
    Get-Process -Name "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

if (-not $SkipClean) {
    foreach ($name in @("build", ".dart_tool")) {
        $p = Join-Path $root $name
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "Removed build + .dart_tool (if not locked)."
}

flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$defines = @(Get-DeepseekDartDefineArgs)
if ($defines.Length -eq 0) {
    Write-Warning "No DeepSeek key found. Create secrets\deepseek_api_key.txt or pass --dart-define=DEEPSEEK_API_KEY=..."
} else {
    Write-Host "Using DeepSeek key from secrets\deepseek_api_key.txt"
}
flutter run -d chrome @defines
