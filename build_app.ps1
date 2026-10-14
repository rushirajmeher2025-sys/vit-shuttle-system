Write-Host "Building Flutter APK for VIT Shuttle System..." -ForegroundColor Cyan

Set-Location shuttle_flutter_app

Write-Host "Cleaning project..." -ForegroundColor Yellow
flutter clean

Write-Host "Fetching dependencies..." -ForegroundColor Yellow
flutter pub get

Write-Host "Building release APK..." -ForegroundColor Yellow
flutter build apk --release

Write-Host "Build complete! APK is located at: shuttle_flutter_app/build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor Green
