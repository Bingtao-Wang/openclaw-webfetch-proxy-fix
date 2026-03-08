# Debug Guide: How to verify the patch is working

## Quick Check

After applying the patch and restarting the gateway, ask your bot:

> Please use web_fetch to access https://github.com

If it returns GitHub's page content instead of an error, the patch is working.

## Detailed Verification

### 1. Start gateway with visible logs

Instead of running gateway in the background, start it with logs visible:

```powershell
$env:HTTP_PROXY = 'http://127.0.0.1:7897'
$env:HTTPS_PROXY = 'http://127.0.0.1:7897'
openclaw gateway 2>&1 | Tee-Object -FilePath gateway-debug.log
```

### 2. Check for debug output

After triggering a web_fetch request, look in the logs for:

**Success** (patch working):
```
[PATCH-DEBUG-*] mode=trusted_env_proxy hasProxy=true url=github.com
[PATCH-DEBUG-*] Using EnvHttpProxyAgent, skipping DNS
```

**Failure** (patch NOT applied or wrong file):
```
[PATCH-DEBUG-*] mode=strict hasProxy=true url=github.com
[tools] web_fetch failed: getaddrinfo ENOTFOUND github.com
```

**No debug output** — the patched file isn't being loaded. Check which `fetch-guard-*.js` files exist and ensure ALL are patched.

### 3. Verify DNS behavior

Run this test script to confirm your DNS environment:

```javascript
// Save as test-dns.cjs in the openclaw directory
const dns = require('dns');
(async () => {
    try {
        const r = await dns.promises.lookup('github.com', { all: true });
        console.log('dns.lookup:', r);
    } catch (e) {
        console.log('dns.lookup FAILED:', e.code);
    }
    try {
        const r = await dns.promises.resolve4('github.com');
        console.log('dns.resolve4:', r);
    } catch (e) {
        console.log('dns.resolve4 FAILED:', e.code);
    }
})();
```

Expected output in China with Clash fake-ip:
```
dns.lookup FAILED: ENOTFOUND      ← This is why web_fetch fails without the patch
dns.resolve4: [ '198.18.0.4' ]    ← Clash fake-ip address
```

### 4. Verify proxy connectivity

```powershell
# Test proxy is accessible
curl -x http://127.0.0.1:7897 -I https://api.github.com

# Test env vars are set
echo $env:HTTP_PROXY
echo $env:HTTPS_PROXY
```

### 5. Count patched files

```powershell
$dist = "$env:APPDATA\npm\node_modules\openclaw\dist"

# Should return 5 files (one per runWebFetch copy):
Get-ChildItem $dist -Recurse -Filter "*.js" |
    Select-String "useEnvProxy: true," |
    Select-Object -ExpandProperty Filename -Unique

# Should return 5 files (one per fetch-guard copy):
Get-ChildItem $dist -Recurse -Filter "fetch-guard-*.js" |
    Select-String "if \(mode === GUARDED_FETCH_MODE" |
    Select-Object -ExpandProperty Filename -Unique
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `mode=strict` in debug log | Patch A not applied to the right file | Re-run `patch-openclaw-proxy.ps1` |
| No debug log output | Gateway still running old code | Kill ALL node processes and restart |
| `ENOTFOUND` despite `mode=trusted_env_proxy` | Patch B not applied (DNS still runs first) | Check ALL `fetch-guard-*.js` files |
| `ECONNREFUSED 127.0.0.1:7897` | Clash proxy not running | Start Clash Verge first |
| Patch works then stops after update | `npm update openclaw` overwrote files | Re-run patch script |
