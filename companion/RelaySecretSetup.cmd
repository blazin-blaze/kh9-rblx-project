@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -Command "$settings=Get-Content -LiteralPath './bridge/relay.local.json' -Raw | ConvertFrom-Json; Set-Clipboard -Value $settings.serverToken; $state=Get-Content -LiteralPath './bridge/host-state.json' -Raw | ConvertFrom-Json; Write-Host 'Relay credential copied. Paste into Creator Dashboard > kh9 roblox project > Secrets > Create Secret.'; Write-Host 'Name: VOICE_RELAY_SERVER_TOKEN'; Write-Host ('Domain: '+([Uri]$state.url).Host); Write-Host 'For solo Studio testing, add the same secret under Experience Settings > Security > Local Secrets.'"
pause
