@echo off
title Ather Rover v3 - build and run
cd /d "%~dp0"
set "FL=C:\Users\jalan\flutter\bin\flutter.bat"
set "ADB=C:\Users\jalan\AppData\Local\Android\Sdk\platform-tools\adb.exe"
if not exist logs mkdir logs
echo started %date% %time% > logs\00_started.txt
echo [1/7] flutter --version
call "%FL%" --version > logs\01_version.txt 2>&1
echo [2/7] flutter pub get
call "%FL%" pub get > logs\02_pubget.txt 2>&1
echo [3/7] flutter analyze
call "%FL%" analyze > logs\03_analyze.txt 2>&1
echo exit %errorlevel% >> logs\03_analyze.txt
echo [4/7] flutter test
call "%FL%" test > logs\04_test.txt 2>&1
echo exit %errorlevel% >> logs\04_test.txt
echo [5/7] finding phone
"%ADB%" devices > logs\05_devices.txt 2>&1
set "DEV="
for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices') do if "%%b"=="device" if not defined DEV set "DEV=%%a"
echo phone: %DEV% >> logs\05_devices.txt
echo [6/7] flutter run (release, installs on the phone)
call "%FL%" run -d %DEV% --release > logs\06_run.txt 2>&1
echo exit %errorlevel% >> logs\06_run.txt
echo finished %date% %time% > logs\07_finished.txt
echo [7/7] done
