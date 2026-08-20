#!/usr/bin/env bash
set -e

# Builds and renames all APKs and the App Bundle on Linux

echo "Cleaning..."
flutter clean
flutter pub get

echo "Building split per ABI..."
flutter build apk --split-per-abi

echo "Building combined APK..."
flutter build apk

echo "Building App Bundle..."
flutter build appbundle

echo "Renaming files..."
SHA=$(git rev-parse --short=7 HEAD)

mv build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "build/app/outputs/flutter-apk/stickers-${SHA}-arm64-v8a.apk"
mv build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk "build/app/outputs/flutter-apk/stickers-${SHA}-armeabi-v7a.apk"
mv build/app/outputs/flutter-apk/app-x86_64-release.apk "build/app/outputs/flutter-apk/stickers-${SHA}-x86_64.apk"
mv build/app/outputs/flutter-apk/app-release.apk "build/app/outputs/flutter-apk/stickers-${SHA}.apk"

echo "Done!"
