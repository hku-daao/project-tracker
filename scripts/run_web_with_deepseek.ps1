# Run Flutter web (Chrome) with DEEPSEEK_API_KEY from secrets/deepseek_api_key.txt
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
. (Join-Path $PSScriptRoot "deepseek_define.ps1")

$defines = @(Get-DeepseekDartDefineArgs)
if ($defines.Length -eq 0) {
    Write-Warning "No key found. Create secrets\deepseek_api_key.txt (see secrets\deepseek_api_key.txt.example)."
} else {
    Write-Host "Using DeepSeek key from secrets\deepseek_api_key.txt"
}

flutter run -d chrome @defines @args
