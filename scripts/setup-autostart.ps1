# ============================================
# Register Windows Task Scheduler for auto-start
# Run as Administrator!
#
# Creates 3 tasks:
#   1. Start Clash Verge on login
#   2. Start OpenClaw Gateway 30s after login (with proxy detection)
#   3. Monitor gateway every 2 minutes
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File setup-autostart.ps1
# ============================================

param(
    [string]$ClashExe = 'C:\Program Files\Clash Verge\Clash Verge.exe',
    [string]$StartScript = 'E:\OpenClawDOC\start-gateway.ps1',    # <-- Modify
    [string]$MonitorScript = 'E:\OpenClawDOC\monitor-gateway.ps1'  # <-- Modify
)

# Task 1: Start Clash Verge on login
$clashAction = New-ScheduledTaskAction -Execute $ClashExe
$clashTrigger = New-ScheduledTaskTrigger -AtLogOn
$clashSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName "OpenClaw-ClashVerge-AutoStart" `
    -Action $clashAction `
    -Trigger $clashTrigger `
    -Settings $clashSettings `
    -Description "Auto-start Clash Verge proxy on login" `
    -Force

Write-Host "Registered: OpenClaw-ClashVerge-AutoStart"

# Task 2: Start Gateway 30s after login
$gwAction = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$StartScript`""
$gwTrigger = New-ScheduledTaskTrigger -AtLogOn
$gwTrigger.Delay = 'PT30S'
$gwSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName "OpenClaw-Gateway-AutoStart" `
    -Action $gwAction `
    -Trigger $gwTrigger `
    -Settings $gwSettings `
    -Description "Auto-start OpenClaw Gateway after Clash proxy is ready" `
    -Force

Write-Host "Registered: OpenClaw-Gateway-AutoStart"

# Task 3: Monitor (optional)
if (Test-Path $MonitorScript) {
    $monAction = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$MonitorScript`""
    $monTrigger = New-ScheduledTaskTrigger -AtLogOn
    $monTrigger.Delay = 'PT2M'
    $monSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Days 365)

    Register-ScheduledTask -TaskName "OpenClaw-Gateway-Monitor" `
        -Action $monAction `
        -Trigger $monTrigger `
        -Settings $monSettings `
        -Description "Monitor OpenClaw Gateway and Clash proxy status" `
        -Force

    Write-Host "Registered: OpenClaw-Gateway-Monitor"
}

Write-Host ""
Write-Host "Done! Login startup order:"
Write-Host "  1. Clash Verge starts immediately"
Write-Host "  2. 30s later: start-gateway.ps1 checks proxy and starts gateway"
Write-Host "  3. 2min later: monitor-gateway.ps1 starts continuous monitoring"
