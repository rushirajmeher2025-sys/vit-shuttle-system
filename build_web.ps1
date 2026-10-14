Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Building VIT Shuttle Web App for Vercel  " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$env:PATH = "C:\flutter\flutter\bin;" + $env:PATH

Set-Location "$PSScriptRoot\shuttle_flutter_app"
flutter build web --release

if (Test-Path "$PSScriptRoot\shuttle_flutter_app\vercel.json") {
    Copy-Item -Path "$PSScriptRoot\shuttle_flutter_app\vercel.json" -Destination "$PSScriptRoot\shuttle_flutter_app\build\web\vercel.json" -Force
}

Write-Host ""
Write-Host "Build completed successfully!" -ForegroundColor Green
Write-Host "Production bundle is located at: shuttle_flutter_app\build\web" -ForegroundColor Green
Write-Host "To deploy to Vercel, simply drag & drop the 'shuttle_flutter_app\build\web' folder to https://vercel.com/new" -ForegroundColor Yellow
