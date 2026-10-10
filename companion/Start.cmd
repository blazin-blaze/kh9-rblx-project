@echo off
cd /d "%~dp0"
if exist "%~dp0LocalConfig.cmd" call "%~dp0LocalConfig.cmd"
"%~dp0runtime\python.exe" -u "%~dp0bridge\console_bridge.py" %*
pause
