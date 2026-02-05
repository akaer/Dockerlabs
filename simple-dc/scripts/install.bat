@echo off
cd /d %~dp0

powershell -ExecutionPolicy Unrestricted -noProfile -File "c:\OEM\configure.ps1"

exit 0
