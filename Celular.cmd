@echo off
rem Opens the local web server to phones on the same Wi-Fi (docs/MOBILE.md).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\celular.ps1" %*
