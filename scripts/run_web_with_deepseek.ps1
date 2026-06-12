param(
    [string]$ApiBaseUrl
)

# Run Flutter web (Chrome) with DEEPSEEK_API_KEY from secrets/deepseek_api_key.txt
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
. (Join-Path $PSScriptRoot "deepseek_define.ps1")

function Clear-StaleFlutterBuild {
    if (-not (Test-Path "build")) { return }
    try {
        Remove-Item -Recurse -Force "build" -ErrorAction Stop
        Write-Host "Cleared stale build folder"
    } catch {
        Write-Warning @"
Could not delete build\ (often locked on Windows by a prior flutter run, Chrome, or OneDrive).
  Close Chrome for this app and stop any other 'flutter run' (Ctrl+C), then run: flutter clean
  Or pause OneDrive sync briefly. Pass -Clean to run flutter clean before launch.
"@
    }
}

if ($args -contains "-Clean") {
    $args = @($args | Where-Object { $_ -ne "-Clean" })
    flutter clean
} else {
    Clear-StaleFlutterBuild
}

$defines = @(Get-DeepseekDartDefineArgs)
if ($ApiBaseUrl -and $ApiBaseUrl.Trim().Length -gt 0) {
    $defines += "--dart-define=API_BASE_URL=$($ApiBaseUrl.Trim())"
    Write-Host "Using backend API: $($ApiBaseUrl.Trim())"
}
if ($defines.Length -eq 0) {
    Write-Warning "No key found. Create secrets\deepseek_api_key.txt (see secrets\deepseek_api_key.txt.example)."
} else {
    Write-Host "Using DeepSeek key from secrets\deepseek_api_key.txt"
}

flutter run -d chrome @defines @args
