# ============================================
# OpenClaw Gateway Monitor Script
# Runs continuously, checks every 2 minutes:
#   1. Is Clash proxy alive? If not, restart it
#   2. Is Gateway alive? If not, restart it
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File monitor-gateway.ps1
# ============================================

$LogFile = "E:\OpenClawDOC\logs\monitor-gateway.log"  # <-- Modify
$ClashExe = 'C:\Program Files\Clash Verge\Clash Verge.exe'  # <-- Modify
$ProxyPort = 7897           # <-- Modify to your proxy port
$GatewayPort = 18789        # <-- Modify to your gateway port
$GatewayCmd = "$env:HOME\.openclaw\gateway.cmd"  # <-- Modify

$env:HTTP_PROXY  = "http://127.0.0.1:$ProxyPort"
$env:HTTPS_PROXY = "http://127.0.0.1:$ProxyPort"
$env:ALL_PROXY   = "http://127.0.0.1:$ProxyPort"
$env:NO_PROXY    = 'localhost,127.0.0.1'

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] $Message"
    Write-Host $line
    if ($LogFile) { Add-Content -Path $LogFile -Value $line -Encoding UTF8 }
}

function Test-Proxy {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect('127.0.0.1', $ProxyPort)
        $tcp.Close()
        return $true
    } catch { return $false }
}

function Ensure-Clash {
    if (-not (Test-Proxy)) {
        Write-Log "Clash proxy unavailable on port $ProxyPort, attempting to start..."
        $clashProc = Get-Process -Name 'Clash Verge' -ErrorAction SilentlyContinue
        if (-not $clashProc -and (Test-Path $ClashExe)) {
            Start-Process -FilePath $ClashExe -WindowStyle Minimized
            Write-Log "Clash Verge process started"
        }
        for ($i = 0; $i -lt 15; $i++) {
            Start-Sleep -Seconds 2
            if (Test-Proxy) {
                Write-Log "Clash proxy is ready"
                return $true
            }
        }
        Write-Log "WARNING: Clash proxy start timeout (30s)"
        return $false
    }
    return $true
}

Write-Log "========== MONITOR STARTED =========="

while ($true) {
    # Step 1: Ensure Clash proxy is alive
    $proxyOk = Ensure-Clash

    # Step 2: Check gateway
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$GatewayPort" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        Write-Log "Gateway OK (HTTP $($response.StatusCode)) | Proxy: $proxyOk"
    }
    catch {
        Write-Log "Gateway NOT responding on port $GatewayPort, restarting..."
        if (Test-Path $GatewayCmd) {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$GatewayCmd`"" -WindowStyle Hidden
            Write-Log "Gateway restart command issued"
        } else {
            Write-Log "WARNING: gateway.cmd not found at $GatewayCmd"
        }
        Start-Sleep -Seconds 10
    }

    # Wait 2 minutes before next check
    Start-Sleep -Seconds 120
}
