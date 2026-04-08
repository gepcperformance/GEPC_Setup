@echo off
start "" /B powershell -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "& { try { & '%~dp0GEPC_Setup.ps1' } catch {} }"
exit
