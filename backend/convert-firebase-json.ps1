# PowerShell script to convert Firebase service account JSON to single line
# Usage: .\convert-firebase-json.ps1 path\to\firebase-service-account.json

param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile
)

if (-not (Test-Path $InputFile)) {
    Write-Host "Error: File not found: $InputFile" -ForegroundColor Red
    exit 1
}

Write-Host "Reading Firebase JSON from: $InputFile" -ForegroundColor Green

# Read the JSON file
$json = Get-Content $InputFile -Raw -Encoding UTF8

# Remove all line breaks and extra whitespace
$json = $json -replace "`r`n", "" -replace "`n", "" -replace "`r", "" -replace "\s+", " "

# Output to console (for copying)
Write-Host "`n=== Single-line JSON (copy this) ===" -ForegroundColor Yellow
Write-Host $json -ForegroundColor Cyan
Write-Host "`n=== End ===`n" -ForegroundColor Yellow

# Also save to file
$outputFile = "firebase-single-line.txt"
$json | Out-File $outputFile -NoNewline -Encoding UTF8
Write-Host "Saved to: $outputFile" -ForegroundColor Green
Write-Host "`nYou can now copy the JSON above and paste it into Railway/Render environment variables." -ForegroundColor Green
