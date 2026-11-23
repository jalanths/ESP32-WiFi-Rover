@echo off
title Ather Rover v3 - analyze and test
cd /d "%~dp0"
set "FL=C:\Users\jalan\flutter\bin\flutter.bat"
if not exist logs mkdir logs
echo started %date% %time% > logs\10_check_started.txt
call "%FL%" analyze > logs\11_analyze.txt 2>&1
echo exit %errorlevel% >> logs\11_analyze.txt
call "%FL%" test > logs\12_test.txt 2>&1
echo exit %errorlevel% >> logs\12_test.txt
echo finished %date% %time% > logs\13_check_finished.txt
