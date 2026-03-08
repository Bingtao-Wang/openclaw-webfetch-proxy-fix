# OpenClaw web_fetch Proxy Fix - Root Cause Analysis

## Five-layer debugging journey

This document details the full investigation process, including dead ends and lessons learned.

---

## Layer 1: Is the proxy running?

**Hypothesis**: Clash proxy wasn't running when gateway started.

**Result**: Proxy port 7897 was listening, `curl -x proxy https://github.com` returned 200. **Eliminated.**

## Layer 2: Are env vars passed to the process?

**Hypothesis**: `HTTP_PROXY` wasn't reaching the Node.js process.

**Result**: `gateway.cmd` explicitly sets `HTTP_PROXY` before launching Node.js. **Eliminated.**

## Layer 3: Does the code use the proxy?

**Hypothesis**: web_fetch code ignores `HTTP_PROXY` by design.

**Finding**: OpenClaw's network guard has two modes:
- `strict` — ignores proxy env vars (default for web_fetch)
- `trusted_env_proxy` — uses `EnvHttpProxyAgent` from undici

The `useEnvProxy` parameter controls which mode is used. web_fetch defaults to `strict`.

**Action**: Added `useEnvProxy: true` to `withStrictWebToolsEndpoint()`.

**Result**: Still failed. Mode in debug log showed `strict`. **Something else going on.**

## Layer 4: DNS pre-resolution blocks proxy

**Finding**: In `fetch-guard`, the SSRF protection resolves DNS locally BEFORE creating the proxy agent:

```javascript
// Step 1: Local DNS (fails for github.com in China)
const pinned = await resolvePinnedHostnameWithPolicy(hostname, ...);
// Step 2: Only AFTER DNS succeeds, create proxy (never reached!)
if (mode === TRUSTED_ENV_PROXY) dispatcher = new EnvHttpProxyAgent();
```

**Verification** with Node.js:
```javascript
dns.promises.lookup('github.com')   // ENOTFOUND (system DNS fails)
dns.promises.resolve4('github.com') // 198.18.0.4 (Clash fake-ip)
```

**Action**: Reordered logic — check proxy mode first, skip DNS if using proxy.

**Result**: Debug log still showed `mode=strict`. The `useEnvProxy: true` from the wrapper function wasn't reaching the actual web_fetch code path.

## Layer 5: web_fetch bypasses the wrapper function

**THE ACTUAL ROOT CAUSE**

The `runWebFetch()` function calls `fetchWithWebToolsNetworkGuard()` DIRECTLY, without going through `withStrictWebToolsEndpoint()`:

```javascript
// What we patched (withStrictWebToolsEndpoint) - NOT used by web_fetch!
async function withStrictWebToolsEndpoint(params, run) { ... }

// What web_fetch actually calls - needs its own useEnvProxy:
async function runWebFetch(params) {
    const result = await fetchWithWebToolsNetworkGuard({
        url: params.url,
        // NO useEnvProxy here! ← THE BUG
        init: { headers: { ... } }
    });
}
```

**Action**: Added `useEnvProxy: true` directly in `runWebFetch()` call.

**Result**:
```
[PATCH-DEBUG] mode=trusted_env_proxy hasProxy=true url=github.com
[PATCH-DEBUG] Using EnvHttpProxyAgent, skipping DNS
```
**web_fetch successfully accessed github.com!**

---

## Dead ends and lessons

| Dead End | Why It Failed | Lesson |
|----------|--------------|--------|
| Only patched `withStrictWebToolsEndpoint` | web_fetch doesn't use this wrapper | Add debug logs to confirm actual code path |
| Only patched 1 of 5 `fetch-guard` files | OpenClaw bundles multiple copies | Always `grep -r` to find ALL copies |
| Assumed pm2 / env var issue | Surface symptoms misled investigation | Read the exact error message first |
| Didn't check `runWebFetch` source | Only analyzed wrapper functions | Trace the FULL call chain from error to entry |

**Core lesson**: When patching compiled JS, the most reliable approach is to **add debug logging to confirm which code path actually executes**, rather than guessing from static analysis.
