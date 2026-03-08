#!/usr/bin/env bash
# ============================================================
# OpenClaw web_fetch Proxy Patch Script (Linux/macOS)
# Fixes web_fetch to work with HTTP proxy (Clash/V2Ray/SSR)
#
# Usage:
#   chmod +x patch-openclaw-proxy.sh
#   ./patch-openclaw-proxy.sh
#
# After running: restart gateway with `openclaw gateway stop && openclaw gateway`
# ============================================================

set -euo pipefail

# Auto-detect dist path
DIST_PATH="${1:-}"
if [ -z "$DIST_PATH" ]; then
    for candidate in \
        "$HOME/.npm/lib/node_modules/openclaw/dist" \
        "$HOME/.local/share/npm/node_modules/openclaw/dist" \
        "$(npm root -g 2>/dev/null)/openclaw/dist" \
        "$HOME/.openclaw/node_modules/openclaw/dist"; do
        if [ -d "$candidate" ]; then
            DIST_PATH="$candidate"
            break
        fi
    done
fi

if [ -z "$DIST_PATH" ] || [ ! -d "$DIST_PATH" ]; then
    echo "[ERROR] Cannot find OpenClaw dist directory."
    echo "  Specify manually: $0 /path/to/openclaw/dist"
    exit 1
fi

echo "============================================"
echo " OpenClaw web_fetch Proxy Patch (Bash)"
echo "============================================"
echo "Target: $DIST_PATH"
echo ""

PATCH_COUNT=0

# PATCH A: Add useEnvProxy:true to runWebFetch()
echo "[Patch A] Adding useEnvProxy:true to runWebFetch()..."
while IFS= read -r -d '' file; do
    if grep -q 'async function runWebFetch' "$file" && \
       grep -q 'fetchWithWebToolsNetworkGuard' "$file" && \
       ! grep -q 'useEnvProxy: true,' "$file"; then
        sed -i 's/timeoutSeconds: params\.timeoutSeconds,\n\t\t\tinit: { headers: {/timeoutSeconds: params.timeoutSeconds,\n\t\t\tuseEnvProxy: true,\n\t\t\tinit: { headers: {/g' "$file"
        # If sed multiline didn't work, use perl
        perl -i -0pe 's/(timeoutSeconds: params\.timeoutSeconds,\s*)(init: \{ headers: \{)/$1useEnvProxy: true,\n\t\t\t$2/g' "$file"
        echo "  + $(basename "$file")"
        ((PATCH_COUNT++)) || true
    fi
done < <(find "$DIST_PATH" -name "*.js" -print0)

# PATCH B: Reorder fetch-guard DNS/proxy logic
echo ""
echo "[Patch B] Reordering fetch-guard DNS/proxy logic..."
while IFS= read -r -d '' file; do
    if grep -q 'resolvePinnedHostnameWithPolicy' "$file" && \
       grep -q 'EnvHttpProxyAgent' "$file" && \
       ! grep -q 'if (mode === GUARDED_FETCH_MODE.TRUSTED_ENV_PROXY && hasProxyEnvConfigured()) {' "$file"; then
        perl -i -0pe 's/\t\tlet dispatcher = null;\n\t\ttry \{\n\t\t\tconst pinned = await resolvePinnedHostnameWithPolicy\(parsedUrl\.hostname, \{\n\t\t\t\tlookupFn: params\.lookupFn,\n\t\t\t\tpolicy: params\.policy\n\t\t\t\}\);\n\t\t\tif \(mode === GUARDED_FETCH_MODE\.TRUSTED_ENV_PROXY && hasProxyEnvConfigured\(\)\) dispatcher = new EnvHttpProxyAgent\(\);\n\t\t\telse if \(params\.pinDns !== false\) dispatcher = createPinnedDispatcher\(pinned\);/\t\tlet dispatcher = null;\n\t\ttry {\n\t\t\tif (mode === GUARDED_FETCH_MODE.TRUSTED_ENV_PROXY \&\& hasProxyEnvConfigured()) {\n\t\t\t\tdispatcher = new EnvHttpProxyAgent();\n\t\t\t} else {\n\t\t\t\tconst pinned = await resolvePinnedHostnameWithPolicy(parsedUrl.hostname, {\n\t\t\t\t\tlookupFn: params.lookupFn,\n\t\t\t\t\tpolicy: params.policy\n\t\t\t\t});\n\t\t\t\tif (params.pinDns !== false) dispatcher = createPinnedDispatcher(pinned);\n\t\t\t}/g' "$file"
        echo "  + $(basename "$file")"
        ((PATCH_COUNT++)) || true
    fi
done < <(find "$DIST_PATH" -name "fetch-guard-*.js" -print0)

# PATCH C: Update withStrictWebToolsEndpoint
echo ""
echo "[Patch C] Updating withStrictWebToolsEndpoint()..."
while IFS= read -r -d '' file; do
    if grep -q 'async function withStrictWebToolsEndpoint' "$file" && \
       ! grep -q 'useEnvProxy: true }, run)' "$file"; then
        sed -i 's/return await withWebToolsNetworkGuard(params, run);/return await withWebToolsNetworkGuard({ ...params, useEnvProxy: true }, run);/g' "$file"
        echo "  + $(basename "$file")"
        ((PATCH_COUNT++)) || true
    fi
done < <(find "$DIST_PATH" -name "*.js" -print0)

echo ""
echo "============================================"
echo " Patch complete! $PATCH_COUNT patches applied"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Restart gateway: openclaw gateway stop && openclaw gateway"
echo "  2. Make sure HTTP_PROXY is set in your startup script"
echo "  3. Test: ask your bot to web_fetch https://github.com"
