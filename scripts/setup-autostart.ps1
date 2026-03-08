# ============================================
# Register Windows Task Scheduler for auto-start (Proxy-agnostic)
# Run as Administrator!
#
# Creates 2 tasks:
#   1. Start OpenClaw Gateway 30s after login (with proxy port detection)
#   2. Monitor gateway every 2 minutes, auto-restart if down
#
# Your proxy software (Clash, V2Ray, SSR, etc.) should be configured
# to auto-start separately via its own settings.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File setup-autostart.ps1
#
# Configuration:
#   .\setup-autostart.ps1 -StartScript "C:\path\to\start-gateway.ps1"
# ============================================

param(
    [string]$StartScript = '',
    [string]$MonitorScript = ''
)

# Auto-detect script paths (look in same directory as this script)
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
if (-not $StartScript)  { $StartScript  = Join-Path $scriptDir "start-gateway.ps1" }
if (-not $MonitorScript) { $MonitorScript = Join-Path $scriptDir "monitor-gateway.ps1" }

# Validate
if (-not (Test-Path $StartScript)) {
    Write-Host "ERROR: start-gateway.ps1 not found at: $StartScript"
    Write-Host "  Use -StartScript parameter to specify the correct path."
    exit 1
}

# Task 1: Start Gateway 30s after login
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
    -Description "Auto-start OpenClaw Gateway after login (waits for proxy port)" `
    -Force

Write-Host "Registered: OpenClaw-Gateway-AutoStart"

# Task 2: Monitor (starts 2 minutes after login)
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
        -Description "Monitor OpenClaw Gateway, auto-restart if down" `
        -Force

    Write-Host "Registered: OpenClaw-Gateway-Monitor"
} else {
    Write-Host "WARNING: monitor-gateway.ps1 not found at: $MonitorScript (skipped)"
}

Write-Host ""
Write-Host "Done! Login startup order:"
Write-Host "  1. Your proxy software starts (configure auto-start in its own settings)"
Write-Host "  2. 30s later: start-gateway.ps1 checks proxy port and starts gateway"
Write-Host "  3. 2min later: monitor-gateway.ps1 starts continuous monitoring"
Write-Host ""
Write-Host "TIP: Most proxy software (Clash Verge, V2RayN, etc.) has a built-in"
Write-Host "     'Start on boot' option. Enable it in your proxy app's settings."
