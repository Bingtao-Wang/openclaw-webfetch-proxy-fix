# ============================================
# OpenClaw Gateway Monitor Script (Proxy-agnostic)
#
# Runs continuously, checks every 2 minutes:
#   1. Is the proxy port reachable? Log warning if not
#   2. Is Gateway alive? If not, restart it
#
# Works with ANY proxy software (Clash, V2Ray, SSR, etc.)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File monitor-gateway.ps1
#
# Configuration:
#   Edit the variables below, or pass parameters:
#   .\monitor-gateway.ps1 -ProxyPort 7897 -GatewayPort 18789
# ============================================

param(
    [int]$ProxyPort = 7897,
    [int]$GatewayPort = 18789,
    [string]$GatewayCmd = "",
    [string]$LogFile = "",
    [int]$Interval = 120
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
    if ($logDir) { $LogFile = Join-Path (Split-Path $logDir -Parent) "logs\monitor-gateway.log" }
}

# Set proxy env vars
$env:HTTP_PROXY  = "http://127.0.0.1:$ProxyPort"
$env:HTTPS_PROXY = "http://127.0.0.1:$ProxyPort"
$env:ALL_PROXY   = "http://127.0.0.1:$ProxyPort"
$env:NO_PROXY    = 'localhost,127.0.0.1'

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

Write-Log "========== MONITOR STARTED =========="
Write-Log "Proxy port: $ProxyPort | Gateway port: $GatewayPort"
Write-Log "Check interval: ${Interval}s"

while ($true) {
    # Step 1: Check proxy port
    $proxyOk = Test-Port $ProxyPort
    if (-not $proxyOk) {
        Write-Log "WARNING: Proxy port $ProxyPort not reachable (start your proxy software)"
    }

    # Step 2: Check gateway
    $gatewayOk = Test-Port $GatewayPort
    if ($gatewayOk) {
        Write-Log "Gateway OK on port $GatewayPort | Proxy: $proxyOk"
    } else {
        Write-Log "Gateway NOT responding on port $GatewayPort, restarting..."
        if ($GatewayCmd -and (Test-Path $GatewayCmd)) {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$GatewayCmd`"" -WindowStyle Hidden
            Write-Log "Gateway restart command issued"
        } else {
            Write-Log "WARNING: gateway.cmd not found. Set -GatewayCmd parameter."
        }
        Start-Sleep -Seconds 10
    }

    # Wait before next check
    Start-Sleep -Seconds $Interval
}
