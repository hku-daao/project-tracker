# Reads secrets/deepseek_api_key.txt for flutter --dart-define (local builds only).

function Get-DeepseekKeyFilePath {
    Join-Path (Split-Path $PSScriptRoot -Parent) "secrets\deepseek_api_key.txt"
}

function Get-DeepseekDartDefineArgs {
    $path = Get-DeepseekKeyFilePath
    if (-not (Test-Path -LiteralPath $path)) {
        return [string[]]@()
    }
    $key = (Get-Content -LiteralPath $path -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($key)) {
        return [string[]]@()
    }
    # Comma keeps a one-element result as an array (PowerShell otherwise unwraps it).
    return , "--dart-define=DEEPSEEK_API_KEY=$key"
}

function Test-DeepseekKeyConfigured {
    return @(Get-DeepseekDartDefineArgs).Length -gt 0
}
