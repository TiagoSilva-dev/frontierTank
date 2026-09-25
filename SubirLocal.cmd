@echo off
rem Frontier Tank no navegador, tudo neste computador (banco, API, servidor de jogo e o jogo web).
rem Precisa do Docker Desktop aberto. Depois: http://localhost:8000
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\local.ps1" up
if errorlevel 1 pause
