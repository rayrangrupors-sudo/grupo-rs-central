@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
echo.
echo GERADOR DE ATUALIZACAO - GRUPO RS CENTRAL
echo.
set /p VERSION=Digite a nova versao (exemplo 3.8.2): 
if "%VERSION%"=="" (
  echo Versao nao informada.
  pause
  exit /b 1
)
set /p NOTES=Resumo das mudancas: 
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\publicar_atualizacao.ps1" -Version "%VERSION%" -Notes "%NOTES%"
echo.
pause
