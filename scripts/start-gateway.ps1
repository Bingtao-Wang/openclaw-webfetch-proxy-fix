# ============================================
# OpenClaw Gateway Startup Script (Proxy-agnostic)
#
# Before starting the gateway, checks if the configured proxy port
# is reachable. Works with ANY proxy software (Clash, V2Ray, SSR, etc.)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File start-gateway.ps1
#
# Configuration:
#   Edit the variables below, or pass parameters:
#   .\start-gateway.ps1 -ProxyPort 7897 -MaxWait 60
# ============================================

param(
    [int]$ProxyPort = 7897,
    [int]$GatewayPort = 18789,
    [int]$MaxWait = 60,
    [string]$GatewayCmd = "",
    [string]$LogFile = ""
)

# Auto-detect gateway.cmd
if (-not $GatewayCmd) {
    $candidates = @(
        "$env:HOME\.openclaw\gateway.cmd",
        "$env:USERPROFILE\.openclaw\gateway.cmd"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $GatewayCmd = $c; break }
    }
}

# Auto-detect log path
if (-not $LogFile) {
    $logDir = Split-Path $GatewayCmd -Parent
    if ($logDir) { $LogFile = Join-Path (Split-Path $logDir -Parent) "logs\start-gateway.log" }
}

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] $Message"
    Write-Host $line
    if ($LogFile) {
        $dir = Split-Path $LogFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    }
}

function Test-Port {
    param([int]$Port)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect('127.0.0.1', $Port)
        $tcp.Close()
        return $true
    } catch { return $false }
}

# Set proxy env vars
$env:HTTPS_PROXY = "http://127.0.0.1:$ProxyPort"
$env:HTTP_PROXY  = "http://127.0.0.1:$ProxyPort"
$env:ALL_PROXY   = "http://127.0.0.1:$ProxyPort"
$env:NO_PROXY    = 'localhost,127.0.0.1'

Write-Log "========== START-GATEWAY BEGIN =========="
Write-Log "Proxy: http://127.0.0.1:$ProxyPort"
Write-Log "Gateway cmd: $GatewayCmd"

# Step 1: Wait for proxy port to be available
if (-not (Test-Port $ProxyPort)) {
    Write-Log "Proxy port $ProxyPort not available, waiting up to $MaxWait s..."
    Write-Log "  (Please start your proxy software: Clash, V2Ray, SSR, etc.)"
    $waited = 0
    while (-not (Test-Port $ProxyPort) -and $waited -lt $MaxWait) {
        Start-Sleep -Seconds 2
        $waited += 2
        if ($waited % 10 -eq 0) {
            Write-Log "  Still waiting for proxy... ($waited/$MaxWait s)"
        }
    }
    if (-not (Test-Port $ProxyPort)) {
        Write-Log "WARNING: Proxy port $ProxyPort not ready after $MaxWait s, starting gateway anyway"
    } else {
        Write-Log "Proxy port $ProxyPort is ready"
    }
} else {
    Write-Log "Proxy port $ProxyPort is already available"
}

# Step 2: Start gateway
if (-not $GatewayCmd -or -not (Test-Path $GatewayCmd)) {
    Write-Log "ERROR: gateway.cmd not found. Set -GatewayCmd parameter."
    exit 1
}

Write-Log "Starting OpenClaw Gateway..."
Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$GatewayCmd`"" -WindowStyle Hidden
Write-Log "Gateway process launched"

# Step 3: Verify
Start-Sleep -Seconds 8
if (Test-Port $GatewayPort) {
    Write-Log "Gateway verified on port $GatewayPort"
} else {
    Write-Log "Gateway not responding on port $GatewayPort yet (may still be starting)"
}

Write-Log "========== START-GATEWAY END =========="
