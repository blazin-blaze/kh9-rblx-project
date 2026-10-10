@echo off
cd /d "%~dp0"
"%~dp0runtime\python.exe" "%~dp0bridge\console_bridge.py" --devices
pause
