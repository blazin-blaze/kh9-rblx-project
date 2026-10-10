@echo off
cd /d "%~dp0"
"%~dp0runtime\python.exe" -u "%~dp0bridge\host_relay.py" %*
pause
