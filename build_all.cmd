@echo off
REM builds and renames all apks and the appbudle

echo Cleaning...
call flutter clean

echo Building split per abi...
call flutter build apk --split-per-abi

echo Building combined apk...
call flutter build apk

echo Building bundle...
call flutter build appbundle

echo Renaming files...
for /F "tokens=* USEBACKQ" %%F in (`git rev-parse HEAD`) do (set sha=%%F)
set "sha=%sha:~0,7%"

ren .\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk stickers-%sha%-arm64-v8a.apk
ren .\build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk stickers-%sha%-armeabi-v7a.apk
ren .\build\app\outputs\flutter-apk\app-x86_64-release.apk stickers-%sha%-x86_64.apk
ren .\build\app\outputs\flutter-apk\app-release.apk stickers-%sha%.apk
echo Done !