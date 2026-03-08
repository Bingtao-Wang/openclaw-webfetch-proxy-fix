# ============================================
# OpenClaw Gateway Startup Script (with Clash proxy detection + logging)
# Ensures proxy is running before starting the gateway
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File start-gateway.ps1
# ============================================

$LogFile = "E:\OpenClawDOC\logs\start-gateway.log"
$ClashExe = 'C:\Program Files\Clash Verge\Clash Verge.exe'  # <-- Modify to your Clash path
$ProxyPort = 7897                                             # <-- Modify to your proxy port
$MaxWait = 60
$GatewayCmd = "$env:HOME\.openclaw\gateway.cmd"               # <-- Modify to your gateway.cmd path

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
    } catch {
        return $false
    }
}

# Set proxy env vars
$env:HTTPS_PROXY = "http://127.0.0.1:$ProxyPort"
$env:HTTP_PROXY  = "http://127.0.0.1:$ProxyPort"
$env:ALL_PROXY   = "http://127.0.0.1:$ProxyPort"
$env:NO_PROXY    = 'localhost,127.0.0.1'

Write-Log "========== START-GATEWAY BEGIN =========="
Write-Log "Proxy env: HTTP_PROXY=$env:HTTP_PROXY"

# Step 1: Check/start Clash proxy
if (-not (Test-Proxy)) {
    Write-Log "Clash proxy not detected on port $ProxyPort, starting..."

    $clashProc = Get-Process -Name 'Clash Verge' -ErrorAction SilentlyContinue
    if (-not $clashProc -and (Test-Path $ClashExe)) {
        Start-Process -FilePath $ClashExe -WindowStyle Minimized
        Write-Log "Clash Verge process started"
    }

    $waited = 0
    while (-not (Test-Proxy) -and $waited -lt $MaxWait) {
        Start-Sleep -Seconds 2
        $waited += 2
        Write-Log "Waiting for Clash proxy... ($waited/$MaxWait s)"
    }

    if (-not (Test-Proxy)) {
        Write-Log "WARNING: Clash proxy not ready after $MaxWait s"
    } else {
        Write-Log "Clash proxy is ready on port $ProxyPort"
    }
} else {
    Write-Log "Clash proxy already running on port $ProxyPort"
}

# Step 2: Start OpenClaw Gateway
Write-Log "Starting OpenClaw Gateway..."
Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$GatewayCmd`"" -WindowStyle Hidden
Write-Log "OpenClaw Gateway process launched"

# Step 3: Verify
Start-Sleep -Seconds 8
try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:18789" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
    Write-Log "Gateway verified: HTTP $($resp.StatusCode)"
} catch {
    Write-Log "Gateway verification: not responding yet (may still be starting)"
}

Write-Log "========== START-GATEWAY END =========="
