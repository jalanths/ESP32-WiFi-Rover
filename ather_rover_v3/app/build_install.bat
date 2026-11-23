@echo off
title Ather Rover v3 - check, build, install
cd /d "%~dp0"
set "FL=C:\Users\jalan\flutter\bin\flutter.bat"
set "ADB=C:\Users\jalan\AppData\Local\Android\Sdk\platform-tools\adb.exe"
if not exist logs mkdir logs
echo started %date% %time% > logs\20_started.txt
call "%FL%" analyze > logs\21_analyze.txt 2>&1
echo exit %errorlevel% >> logs\21_analyze.txt
call "%FL%" test > logs\22_test.txt 2>&1
echo exit %errorlevel% >> logs\22_test.txt
call "%FL%" build apk --release > logs\23_build.txt 2>&1
echo exit %errorlevel% >> logs\23_build.txt
"%ADB%" install -r build\app\outputs\flutter-apk\app-release.apk > logs\24_install.txt 2>&1
echo exit %errorlevel% >> logs\24_install.txt
"%ADB%" shell monkey -p com.example.ather_rover -c android.intent.category.LAUNCHER 1 >> logs\24_install.txt 2>&1
echo finished %date% %time% > logs\25_finished.txt
