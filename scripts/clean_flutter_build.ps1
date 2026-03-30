# Removes build/ and .dart_tool/ when Flutter reports "failed to delete build\flutter_assets"
# (Chrome or OneDrive often locks files under OneDrive paths).
# Usage (from repo root or anywhere):
#   .\scripts\clean_flutter_build.ps1
#   .\scripts\clean_flutter_build.ps1 -KillChrome   # closes all Chrome windows first
param([switch]$KillChrome)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

if ($KillChrome) {
    Get-Process -Name "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

foreach ($name in @("build", ".dart_tool")) {
    $p = Join-Path $root $name
    if (Test-Path -LiteralPath $p) {
        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Removed build + .dart_tool (if not locked). Next:"
Write-Host "  flutter pub get"
Write-Host "  flutter run -d chrome"
