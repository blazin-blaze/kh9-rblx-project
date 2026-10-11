@echo off
cd /d "%~dp0"
"%~dp0runtime\python.exe" -u "%~dp0bridge\configure_stable_relay.py" %*
pause
