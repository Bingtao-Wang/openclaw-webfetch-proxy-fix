# ============================================================
# OpenClaw web_fetch Proxy Patch Script
# Fixes web_fetch to work with HTTP proxy (Clash/V2Ray/SSR)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File patch-openclaw-proxy.ps1
#
# What it does:
#   1. Adds useEnvProxy:true to runWebFetch() calls
#   2. Reorders fetch-guard logic to skip local DNS when proxy is configured
#   3. Updates withStrictWebToolsEndpoint wrapper functions
#
# After running: restart gateway with `openclaw gateway stop && openclaw gateway`
# ============================================================

param(
    [string]$DistPath = "",
    [switch]$DryRun = $false,
    [switch]$Verbose = $false
)

# Auto-detect OpenClaw dist path
if (-not $DistPath) {
    $candidates = @(
        "$env:APPDATA\npm\node_modules\openclaw\dist",
        "$env:HOME\.openclaw\node_modules\openclaw\dist",
        "$env:LOCALAPPDATA\npm\node_modules\openclaw\dist"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $DistPath = $c
            break
        }
    }
}

if (-not $DistPath -or -not (Test-Path $DistPath)) {
    Write-Host "[ERROR] Cannot find OpenClaw dist directory." -ForegroundColor Red
    Write-Host "  Specify manually: .\patch-openclaw-proxy.ps1 -DistPath 'C:\path\to\openclaw\dist'"
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " OpenClaw web_fetch Proxy Patch" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Target: $DistPath"
Write-Host ""

$patchCount = 0
$fileCount = 0

# -------------------------------------------------------
# PATCH A: Add useEnvProxy:true to runWebFetch() calls
# -------------------------------------------------------
Write-Host "[Patch A] Adding useEnvProxy:true to runWebFetch()..." -ForegroundColor Yellow

$filesA = Get-ChildItem -Path $DistPath -Recurse -Filter "*.js" | Where-Object {
    $content = Get-Content $_.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    $content -match 'async function runWebFetch' -and $content -match 'fetchWithWebToolsNetworkGuard'
}

foreach ($file in $filesA) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    $oldPattern = 'const result = await fetchWithWebToolsNetworkGuard({
			url: params.url,
			maxRedirects: params.maxRedirects,
			timeoutSeconds: params.timeoutSeconds,
			init: { headers: {'
    $newPattern = 'const result = await fetchWithWebToolsNetworkGuard({
			url: params.url,
			maxRedirects: params.maxRedirects,
			timeoutSeconds: params.timeoutSeconds,
			useEnvProxy: true,
			init: { headers: {'

    if ($content.Contains($oldPattern)) {
        if (-not $DryRun) {
            $content = $content.Replace($oldPattern, $newPattern)
            Set-Content $file.FullName -Value $content -NoNewline -Encoding UTF8
        }
        $relPath = $file.FullName.Substring($DistPath.Length + 1)
        Write-Host "  + $relPath" -ForegroundColor Green
        $patchCount++
        $fileCount++
    } elseif ($content.Contains('useEnvProxy: true,') -and $content.Contains('runWebFetch')) {
        $relPath = $file.FullName.Substring($DistPath.Length + 1)
        Write-Host "  ~ $relPath (already patched)" -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------
# PATCH B: Reorder fetch-guard DNS/proxy logic
# -------------------------------------------------------
Write-Host ""
Write-Host "[Patch B] Reordering fetch-guard DNS/proxy logic..." -ForegroundColor Yellow

$fetchGuardFiles = Get-ChildItem -Path $DistPath -Recurse -Filter "fetch-guard-*.js"

foreach ($file in $fetchGuardFiles) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    $oldBlock = '		let dispatcher = null;
		try {
			const pinned = await resolvePinnedHostnameWithPolicy(parsedUrl.hostname, {
				lookupFn: params.lookupFn,
				policy: params.policy
			});
			if (mode === GUARDED_FETCH_MODE.TRUSTED_ENV_PROXY && hasProxyEnvConfigured()) dispatcher = new EnvHttpProxyAgent();
			else if (params.pinDns !== false) dispatcher = createPinnedDispatcher(pinned);'

    $newBlock = '		let dispatcher = null;
		try {
			if (mode === GUARDED_FETCH_MODE.TRUSTED_ENV_PROXY && hasProxyEnvConfigured()) {
				dispatcher = new EnvHttpProxyAgent();
			} else {
				const pinned = await resolvePinnedHostnameWithPolicy(parsedUrl.hostname, {
					lookupFn: params.lookupFn,
					policy: params.policy
				});
				if (params.pinDns !== false) dispatcher = createPinnedDispatcher(pinned);
			}'

    if ($content.Contains($oldBlock)) {
        if (-not $DryRun) {
            $content = $content.Replace($oldBlock, $newBlock)
            Set-Content $file.FullName -Value $content -NoNewline -Encoding UTF8
        }
        $relPath = $file.FullName.Substring($DistPath.Length + 1)
        Write-Host "  + $relPath" -ForegroundColor Green
        $patchCount++
        $fileCount++
    } elseif ($content.Contains('if (mode === GUARDED_FETCH_MODE.TRUSTED_ENV_PROXY && hasProxyEnvConfigured()) {')) {
        $relPath = $file.FullName.Substring($DistPath.Length + 1)
        Write-Host "  ~ $relPath (already patched)" -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------
# PATCH C: Update withStrictWebToolsEndpoint wrapper
# -------------------------------------------------------
Write-Host ""
Write-Host "[Patch C] Updating withStrictWebToolsEndpoint()..." -ForegroundColor Yellow

$filesC = Get-ChildItem -Path $DistPath -Recurse -Filter "*.js" | Where-Object {
    $content = Get-Content $_.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    $content -match 'async function withStrictWebToolsEndpoint'
}

foreach ($file in $filesC) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    $oldFunc = 'async function withStrictWebToolsEndpoint(params, run) {
	return await withWebToolsNetworkGuard(params, run);
}'
    $newFunc = 'async function withStrictWebToolsEndpoint(params, run) {
	return await withWebToolsNetworkGuard({ ...params, useEnvProxy: true }, run);
}'

    if ($content.Contains($oldFunc)) {
        if (-not $DryRun) {
            $content = $content.Replace($oldFunc, $newFunc)
            Set-Content $file.FullName -Value $content -NoNewline -Encoding UTF8
        }
        $relPath = $file.FullName.Substring($DistPath.Length + 1)
        Write-Host "  + $relPath" -ForegroundColor Green
        $patchCount++
    } elseif ($content.Contains('useEnvProxy: true }, run)')) {
        $relPath = $file.FullName.Substring($DistPath.Length + 1)
        Write-Host "  ~ $relPath (already patched)" -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host " DRY RUN - no files modified" -ForegroundColor Yellow
} else {
    Write-Host " Patch complete!" -ForegroundColor Green
}
Write-Host "  $patchCount patches applied across $fileCount files" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if (-not $DryRun -and $patchCount -gt 0) {
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Restart gateway:  openclaw gateway stop && openclaw gateway"
    Write-Host "  2. Make sure HTTP_PROXY is set in your gateway startup script"
    Write-Host "  3. Test: ask your bot to web_fetch https://github.com"
    Write-Host ""
    Write-Host "Note: Re-run this script after every OpenClaw update (npm update openclaw)"
}
