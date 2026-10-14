#!/bin/bash
echo "Building Flutter APK for VIT Shuttle System..."

cd shuttle_flutter_app || exit

echo "Cleaning project..."
flutter clean

echo "Fetching dependencies..."
flutter pub get

echo "Building release APK..."
flutter build apk --release

echo "Build complete! APK is located at: shuttle_flutter_app/build/app/outputs/flutter-apk/app-release.apk"
