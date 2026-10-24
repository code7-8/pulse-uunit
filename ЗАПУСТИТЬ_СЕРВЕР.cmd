@echo off
chcp 65001 >nul
title Пульс — сервер
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-Server.ps1"
if errorlevel 1 pause

