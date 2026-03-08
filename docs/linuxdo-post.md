# [分享] 解决 OpenClaw web_fetch 在国内无法访问 GitHub 的问题（附一键修复脚本）

## 背景

最近在用 OpenClaw 搭 bot，配了 Telegram 频道，想让 bot 用 `web_fetch` 工具帮我抓取 GitHub 页面内容。

代理开了，`gateway.cmd` 里也设了 `HTTP_PROXY`，`curl` 测试代理完全正常：

```bash
curl -x http://127.0.0.1:7897 -I https://github.com
# HTTP/2 200 ✅
```

但 bot 每次调用 `web_fetch` 就报错：

```
[tools] web_fetch failed: getaddrinfo ENOTFOUND github.com
```

![修复前报错截图](https://github.com/Bingtao-Wang/openclaw-webfetch-proxy-fix/raw/main/docs/ENOTFOUND%20github.com.png)

折腾了好久，最终定位到是 **OpenClaw 源码层面的 bug**，不是配置问题。这里分享完整的排查过程和修复方案。

---

## 根因分析

翻了 OpenClaw 编译后的 JS 代码（`%APPDATA%\npm\node_modules\openclaw\dist\`），发现两个问题：

### 问题一：web_fetch 根本没开代理模式

OpenClaw 的网络请求有个 SSRF 安全守卫，分两种模式：
- `strict` — 忽略 `HTTP_PROXY` 环境变量（**web_fetch 默认就是这个**）
- `trusted_env_proxy` — 读取 `HTTP_PROXY`，通过 undici 的 `EnvHttpProxyAgent` 走代理

`runWebFetch()` 调用底层函数时，没传 `useEnvProxy: true`，所以你在环境变量里设什么都没用，代码直接忽略了。

### 问题二：DNS 预解析挡在代理前面

就算手动开了代理模式，SSRF 守卫的代码逻辑是这样的：

```
请求 github.com
  ① 先做本地 DNS 解析 (getaddrinfo)
  ② DNS 成功后，才创建代理 agent
```

在国内，`github.com` 的本地 DNS 解析直接失败（特别是用 Clash fake-ip 模式时，`getaddrinfo` 返回 `ENOTFOUND`），代码在第 ① 步就挂了，永远走不到第 ② 步创建代理。

**简单来说**：代理没开 + DNS 挡路 = 双重 bug。

---

## 修复方案

修改两处编译后的 JS 代码：

**Patch A**：在 `runWebFetch()` 的调用处加上 `useEnvProxy: true`，让 web_fetch 走代理模式

**Patch B**：调换 `fetch-guard` 里的逻辑顺序——检测到代理环境变量时，**先创建代理 agent，跳过本地 DNS**，让代理服务器负责远程解析

```
修复后的请求流程:
  web_fetch("github.com")
    → mode=trusted_env_proxy
    → 检测到 HTTP_PROXY → 创建 EnvHttpProxyAgent（跳过本地 DNS）
    → 代理做远程 DNS 解析
    → ✅ 200 OK
```

---

## 一键修复

已经写好了自动 patch 脚本，自动检测 OpenClaw 安装路径，找到所有需要修改的文件（编译后有 5 个副本），批量打补丁。

```powershell
git clone https://github.com/Bingtao-Wang/openclaw-webfetch-proxy-fix.git
cd openclaw-webfetch-proxy-fix
powershell -ExecutionPolicy Bypass -File scripts/patch-openclaw-proxy.ps1
```

Linux / macOS 用户：
```bash
bash scripts/patch-openclaw-proxy.sh
```

然后重启网关：
```bash
openclaw gateway stop
openclaw gateway
```

> **注意代理端口**：脚本默认端口 `7897`（Clash）。如果你用的是其他代理，记得改 `gateway.cmd` 里的端口。
>
> | 代理软件 | 默认 HTTP 端口 |
> |---------|---------------|
> | Clash Verge / CFW | `7897` |
> | V2RayN | `10808` |
> | Shadowsocks | `1080` |
> | Surge | `6152` |

修复后效果：

![修复后 web_fetch 成功](https://github.com/Bingtao-Wang/openclaw-webfetch-proxy-fix/raw/main/docs/Web_fetch_%E6%88%90%E5%8A%9F.png)

---

## 附赠：网关自启动 + 崩溃自动恢复

项目里还包含几个自动化脚本，**不绑定任何特定代理软件**，只检查代理端口是否通：

| 脚本 | 功能 |
|------|------|
| `start-gateway.ps1` | 启动网关前自动等待代理端口就绪，超时仍启动 |
| `monitor-gateway.ps1` | 每 2 分钟检查网关状态，挂了自动重启 |
| `setup-autostart.ps1` | 注册 Windows 任务计划，开机自动启动网关 + 监控 |

代理软件的自启动请在软件自身设置里开启（Clash Verge: Settings → Start with System）。

```powershell
# 一键注册开机自启动（管理员权限）
powershell -ExecutionPolicy Bypass -File scripts/setup-autostart.ps1
```

---

## 排查过程中的弯路

分享几个踩过的坑，希望能帮到后来人：

| 尝试 | 为什么没用 |
|------|-----------|
| 只改了 `withStrictWebToolsEndpoint` 函数 | `runWebFetch()` 根本不走这个函数，是直接调用底层 |
| 只改了 1 个 `fetch-guard` 文件 | OpenClaw 编译后有 **5 个副本**，必须全部改 |
| 以为是环境变量没传进去 | 代码层面就没读环境变量，传了也没用 |
| 用 pm2 管理网关进程 | 导致终端一直闪烁，直接用 `gateway.cmd` 更稳定 |

**最大的教训**：排查编译后的 JS 代码，不要靠猜，加 `console.log` 确认实际执行路径最靠谱。

---

## 适用环境

- **OS**：Windows 10/11（脚本）、Linux/macOS（Patch 脚本有 Bash 版本）
- **OpenClaw**：v2026.2.x ~ v2026.3.x（其他版本原理相同）
- **代理**：任何本地 HTTP 代理（Clash、V2Ray、SSR、Shadowsocks 等）
- **Node.js**：v18+
- **注意**：OpenClaw 更新后补丁会被覆盖，需重新运行 patch 脚本

---

## 项目地址

**GitHub**: https://github.com/Bingtao-Wang/openclaw-webfetch-proxy-fix

包含完整的 patch 脚本、自动化脚本、根因分析文档和调试指南。MIT 协议，随意使用。

项目开源在 GitHub，觉得有用的话点个 Star 支持一下 :point_right: [openclaw-webfetch-proxy-fix](https://github.com/Bingtao-Wang/openclaw-webfetch-proxy-fix)

遇到问题欢迎提 issue 或在楼下回复。
