@echo off
cd /d "%~dp0"
"%~dp0runtime\python.exe" -u "%~dp0bridge\console_bridge.py" --team-test %*
pause
