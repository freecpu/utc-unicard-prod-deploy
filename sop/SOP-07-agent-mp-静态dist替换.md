# SOP-07：agent-mp 静态 dist 生产替换（S6 前端，生产第四台机）

- 版本：v1.0（2026-11-23）
- 授权来源：REQ-20261113-01《M5 生产上线批次计划》。G5（后端首次部署）/G6（前端首次部署＋nginx 公网接线）于 **2026-11-20**
  执行完毕，G7（B 端路由脱困＋登录门禁）于 **2026-11-21** 执行完毕，均已验收闭合。
  本规程由 `变更留痕/20261119-G5G6首次部署方案/00-部署方案-v1.1-已裁.md` §二十四/§二十五 的实测流水抽出，
  **不含任何未执行过的步骤**；凡与实测流水不同之处均已逐条标注并说明理由。
- 授权：**每次替换仍须按动作显式授权**，授权串形如 `AGENT-MP-WEB-swap-<日期>`（绑动作不可复用）。
  本规程的存在不等于授权；只编写规程不需要授权。
- 执行分工：默认＝主管出命令，用户在生产机执行。
- **覆盖边界**：只管 `/data/apps/agent-mp/dist` 下的静态件。
  后端（Docker compose：`agentmp-app` ＋ `agentmp-redis`，仅回环 7013）不在本规程内；
  nginx 站点配置 `agentmp.conf` 是**禁动件**，本规程不允许修改它。
- 共同性质：纯静态文件替换，**零服务重启、零 nginx reload**（root 路径不变，nginx 按请求读盘）。

> ★ 与 `SOP-04 §C.1`「禁止 nginx reload」的分界（此前无成文判据，此处定清）：
> SOP-04 禁 reload 的理由是**那两台是共享机**，reload 会波及同机全部 vhost。
> 本机是 agent-mp **独占机**（`sites-enabled` 只有一个承载本栈的 symlink），reload 不会波及他人，
> 故 G6 接线时 reload 是合法且必要的。但——**纯静态 dist 替换依旧不需要 reload**，
> 只有改 vhost 才 reload，而改 vhost 不属于本规程。

---

## 0. 坐标与现役锚（G7 实测 2026-11-21）

- 机：ssh 别名 `runyd-223-4-12-235`（Port 22，专用钥匙；出口 IP 不固定，暂时无白名单）
- nginx：**1.24.0 (Ubuntu)**；站点 `/etc/nginx/sites-available/agentmp.conf`（`sites-enabled` 唯一 symlink）
- 静态根：`/data/apps/agent-mp/dist`
- 入口：`https://www.xhc123.work`（`server_name www.xhc123.work xhc123.work`；80 侧除 MP_verify 两枚外一律 `301 → https`）
- 反代：`/api/` → **127.0.0.1:7013**（后端仅绑回环；Host/X-Real-IP/X-Forwarded-For/X-Forwarded-Proto，`proxy_read_timeout 120s`）
- 证书：`/data/ssl/www.xhc123.work.pem` / `.key`（key 已 600）；CN=www.xhc123.work，WoTrus RSA DV SSL CA 2，`Verify return code: 0 (ok)`
- 禁动件（**本规程全程不改**）：

  | 件 | 坐标 | sha256 | 字节 |
  |---|---|---|---|
  | nginx 站点配置 | `/etc/nginx/sites-available/agentmp.conf` | `2e8fbc15e0ef0bf88c6ac7f4fcc44bdce3d4cbb9c9215df492cba6159dac40a8` | 2,830 |
  | 微信 MP 校验件 ① | `/data/apps/agent-mp/MP_verify_SoTNuLQw5OgweaCg.txt` | 未采（G6 仅记 disk sha 前缀 `d220661e`） | 16 |
  | 微信 MP 校验件 ② | `/data/apps/agent-mp/MP_verify_KDA52QyFQzUsiMnR.txt` | 未采（G6 仅记 disk sha 前缀 `7548e244`） | 16 |

  → 两枚 MP_verify **在 dist 之外**，由 vhost 的 `location = /MP_verify_*.txt { alias ...; }` 精确承接（80/443 双侧各一份）。
  **不得移进 dist，不得删除** —— 移走即微信域名校验失效。
- 凭据交付件目录：`/data/apps/agent-mp-cred/`（目录 700 / 文件 600，属主 runyd）。
  **这是唯一合法位置；任何凭据文件不得出现在 web root 内。**

### 0.1 现役五件（G7 后；`CURRENT_FILES` 事实源＝`anchors/agent-mp.env`）

| 文件 | sha256 | 字节 |
|---|---|---|
| `index.html` | `bd337e78d9a3f783a396d791a49ac965ac05a7100ec01ec5e547b4e1c52a9f80` | 483 |
| `umi.8f0720bb.js` | `2fba8e738f2cd626b3fd9b2d1f428db2d6a8cb57421068b8ac87dce3bcc0586c` | 1,764,230 |
| `umi.478b4bfc.css` | `bfa59d934c915bcd879394630767036b9db3da91ba43be23cc6b3478c93b25d5` | 402,044 |
| `static/help.c0d849ee.jpeg` | `397e6f7e40f965cbff94c6b375445d5d177753089238937c699e8907ff95ae29` | 42,392 |
| `static/menu.429358a6.png` | `d12a11acd658c99bfe8c91fadb4a04146c6a07158a0acca244ecd75cdd653bdc` | 10,140 |

### 0.2 回滚材料（G6 三锚，完整性哈希）

| 文件 | sha256 | 字节 |
|---|---|---|
| `index.html` | `743a11b37ec0968c776237650cf337f6978706290b4038ff9e8496018a95024d` | 483 |
| `umi.65bb8d50.js` | `3cc5a3e43978f507b1444b57bab72dff1004588e4ac215cd942f697418594adf` | 1,764,058 |
| `umi.730fc955.css` | `c27effd14763e9a8afe0d482266343371e71ef367aaf0412216129fa967e4113` | 402,044 |

`static/help.c0d849ee.jpeg` 与 `static/menu.429358a6.png` 在 G6→G7 之间**逐字节未变**，故回滚不需换这两件。

> ★ dist 内**同时存在**旧的 `umi.65bb8d50.js` 与 `umi.730fc955.css`（G7 有意保留作回滚材料）。
> 因此 dist 实际文件数 **多于** 五件——这是**预期形态，不是残留垃圾**，不得清理。

---

## 1. 与另两套前端的差异（动手前必读）

| 维度 | admin-web（SOP-04 §A） | official-web（SOP-04 §B） | **agent-mp（本节）** |
|---|---|---|---|
| 构建形态 | Vite（`assets/index.<hash>.js`） | umi（根级 `umi.<hash>.js`） | umi（根级，同 official-web） |
| 静态根 | `/data/html/ryd-utc-admin/dist` | `/usr/local/ryd-unicard/bin/dist` | `/data/apps/agent-mp/dist` |
| 备份落点 | 同目录 | **必须落 `/data`**（根分区 94% 满） | 同目录（位于 `/data` 下，分区充裕） |
| 后端 | 本机 8001 | 本机 7003 | **本机 7013，Docker，仅绑回环** |
| SPA 兜底 | 无记录 | 无记录 | **有**：`try_files $uri $uri/ /index.html` |
| 静态缓存 | 无记录 | HTML 无 Cache-Control（X5 启发式缓存风险） | js/css `expires 7d` ＋ `Cache-Control: public, immutable`；HTML 无 Cache-Control |
| 切换手法 | staging＋旧资源并留＋双 `mv` | 同 admin-web | **原地覆盖**（`cp -a` 进 dist，旧 umi 件保留） |
| 回滚 | `dist.pre-G2-*` | `dist.pre-G4-*` | `dist.pre-<批次>-*`；已有历史件 `dist-bak-g7-20261121` |

**两个必须沿用的 agent-mp 专属纪律**：
1. **SPA 兜底使"任何未知路径返回 200"成为正常行为** → 暴露面判据只能是**内容级**（见 §10 判例一）。
2. **浏览器缓存会掩盖发布** → 判定"是否生效"必须先确认取到的是新 index（见 §10 判例三）。

---

## 2. 前置（只读，逐条通过才允许进入 §3）

1. 现役五件 sha256 对 §0.1 **逐字**；不等＝漂移，停手查清后再动。
2. 禁动件三件对 §0 表格：`agentmp.conf` sha == `2e8fbc15…`（2830 B）；MP_verify 两枚存在且 `len=16`。
3. 磁盘：`df -h /data` 余量 ≥ 交付件体积 ×3（staging＋备份＋余量）。
4. 后端健康：`curl -s http://127.0.0.1:7013/api/web/health` → `200` `OK`。
   后端不健康时**先查后端**，不得用前端替换去掩盖。
5. 其它用户在线检查：该机曾有 X11 会话（部署窗口需协调）；`who` 复核。
6. 若本次改动涉及**路由/布局/构建配置**，确认已准备运行期实测手段（§6 第三路），否则不许启 §5。

---

## 3. 产物准入（缺一即停，退出码 20）

按 `SOP-00 §6` 校验三件套，本规程只执行准入、**不执行构建**：

| 件 | 判据 |
|---|---|
| `dist-<7位短commit>/` | 目录名短 commit == BUILD-INFO 的 `COMMIT` 前 7 位 |
| `BUILD-INFO` | 六字段齐全，且 **`PROFILE=prod`**（dev/test 一律拒收） |
| `SHA256SUMS.txt` | `sha256sum -c` 全 OK；条目数 == staging 实际文件数 |

> ★ 清单必须是 `sha256sum` **原生格式**（每行 `<64位hex><两空格><相对路径>`）。
> 带字节数列的清单会让 `sha256sum -c` 直接报格式错 —— 字节数另列在 BUILD-INFO 或清单注释行，
> **不得与 hash 写在同一列**（`SOP-00 §6.2` 已按此修正）。

**形态校验（本机专属）**：必须是 umi 形态 —— `index.html` ＋ 根级 `umi.<hash>.js` ＋ `umi.<hash>.css` ＋ `static/`。
出现 `assets/index.<hash>.js` 说明拿错了另一个项目的产物，立即停。

---

## 4. 备份（★ 回滚唯一来源）

```bash
ssh runyd-223-4-12-235 'cd /data/apps/agent-mp && \
  cp -a dist dist.pre-<批次>-<日期> && \
  sha256sum dist.pre-<批次>-<日期>/index.html && \
  ls -ld dist dist.pre-<批次>-<日期> && df -h /data'
```

备份 `index.html` 的 sha **必须等于** §0.1 的 `bd337e78…`。备份在用户确认前**严禁删除**。
命名按 `SOP-06 §3A.8` 新规：`dist.pre-<批次>-<YYYYMMDD>`；历史件 `dist-bak-g7-20261121` **不改名**。

---

## 5. 替换（原地覆盖，先资源后 index）

```bash
# 本地：上传到同分区 staging
scp -r <新dist本地路径> runyd-223-4-12-235:/data/apps/agent-mp/dist-staging-<批次>

# 机上：校验 → 先落非 index 资源 → 最后落 index → 复验
ssh runyd-223-4-12-235 -n 'cd /data/apps/agent-mp && \
  ( cd dist-staging-<批次> && sha256sum -c SHA256SUMS.txt ) && \
  find dist-staging-<批次> -type f ! -name index.html -exec cp -a {} dist/ \; && \
  cp -a dist-staging-<批次>/index.html dist/index.html && \
  sha256sum dist/index.html'
```

- `-n` 强制：脚本经管道喂入时 ssh 会吞 stdin（§10 判例四）。
- **不删旧 `umi.<hash>` 件**：新的与旧的文件名不同，天然不冲突；旧件是缓存期旧 index 的存活依赖＋回滚材料。
- **顺序「先资源、最后 index」**：`index.html` 是唯一"生效开关"。中途任何中断，旧 index 仍指向旧资源（仍可用），
  不会出现"新 index 指向尚未落位的 js"。
- ★ **与 G7 实测的差异（已披露）**：G7 用 `cp -a dist-staging-g7/. dist/` 一次性覆盖；本规程拆为两步以消除半新半旧风险。
  语义等效、风险更低。**首次按本规程执行时，须在证据里记录实际使用的形态。**
- 属主：`scp` 登录用户即属主用户，覆盖后 `ls -l` 复核与 `dist` 原属性一致。
- staging 在校验与替换完成后清理（只清 `dist-staging-<批次>`，**不清 dist 内的旧 umi 件**）。

---

## 6. 判据（三路，逐路留证）

### 6.1 机内路（在机上执行）

| # | 判据 | 通过条件 |
|---|---|---|
| ① | `curl -sk https://127.0.0.1/ -H "Host: www.xhc123.work"` 的 sha256 | == 新 `index.html` 登记值 |
| ② | 新 `umi.<hash>.js` / `.css` 取回 sha256 | 均 `200`，sha == 交付清单 |
| ③ | 旧 `umi.65bb8d50.js` / `umi.730fc955.css` | 均 `200`（旧缓存页面不白屏） |
| ④ | `/api/web/health` | `200` body=`OK`（后端零波及） |
| ⑤ | 任意不存在路径（如 `/agent/index`） | `200` 且 body sha == `index.html`（SPA 兜底成立） |
| ⑥ | `/.env`、`/.env.bak` | `404`，或 body sha ≠ 任一敏感件且 ≠ `index.html`（见判例一） |
| ⑦ | MP_verify 两枚 × 80/443 两侧 | 四路均 `200`、`len=16`、同侧同值 |
| ⑧ | 80 侧非 MP_verify 路径 | `301`，`Location` 逐字符 `https://$host$request_uri` |
| ⑨ | 安全头 | `X-Frame-Options: SAMEORIGIN`、`X-Content-Type-Options: nosniff`（js/css 亦须在，location 内 `add_header` 会覆盖 server 级，已重申） |
| ⑩ | nginx 零动作 | `agentmp.conf` sha 仍 `2e8fbc15…`；master PID 未变；无 reload |

### 6.2 外部公网路（本地或任意外网机执行）

| # | 判据 | 通过条件 |
|---|---|---|
| ① | 三件 served sha | 与机内路**同锚**（`curl --ssl-no-revoke`；CRL 不可达系本地探针限制，非部署缺陷） |
| ② | `/api/web/health` | `200` `OK` |
| ③ | http 301 | `Location` 逐字符 |
| ④ | MP_verify 两枚（HTTP） | `200`、`len=16` |
| ⑤ | `/.env` | `404` |
| ⑥ | 敏感路径（`.../cred/` 等） | 若 `200`，body **必须是 index 内容**（`body_is_index=YES` ＝合法拒绝形态） |
| ⑦ | 安全头 | 同 6.1 ⑨ |

### 6.3 运行期路（★ 路由/布局/构建配置有改动时**强制**；纯文案/样式可免）

| # | 判据 | 通过条件 |
|---|---|---|
| ① | 外部 `curl "https://www.xhc123.work/index.html?v=<时间戳>"` | 取到**新** hash（防缓存掩盖发布） |
| ② | 浏览器 DevTools → Network | 实际 bundle 名 == 新 `umi.<hash>.js` |
| ③ | `/#/agent/home`（未登录） | 重定向到 `/#/agent/login`，**不跳** `open.weixin.qq.com` |
| ④ | `/#/agent/login` | 表单正常渲染 |
| ⑤ | `/#/iccid` | **仍跳** `open.weixin.qq.com`（appid `wxb325ceaec334362e`）—— C 端授权壳必须保持 |
| ⑥ | `/#/` | 首页「牛量星球」正常 |

> ★ 6.3 ⑤ 是**负向判据**：B 端修复不得把 C 端授权壳一起改掉。G7 正是靠这一条证明了"只修 B 端、未伤 C 端"。

---

## 7. 回滚

两条路，按改动范围选；**两条都不需要重启、不需要 reload**。

**(a) 整目录恢复**（新增/删除文件或大范围变更时用）

```bash
ssh runyd-223-4-12-235 -n 'cd /data/apps/agent-mp && \
  mv dist dist.failed-<批次> && \
  cp -a dist.pre-<批次>-<日期> dist && \
  sha256sum dist/index.html'
```

**(b) 仅回 index**（仅 index 变化、且旧 umi 件仍在 dist 中文内时用 —— G6→G7 就是这种情形）

```bash
ssh runyd-223-4-12-235 -n 'cd /data/apps/agent-mp && \
  cp -a dist.pre-<批次>-<日期>/index.html dist/index.html && \
  sha256sum dist/index.html'
```

回滚后 sha 必须 == §0.1 原值（逐字）。失败现场 `dist.failed-<批次>` 保留供归因。
**回滚后须把实测到的真值回填 `anchors/agent-mp.env`**（`README.md` §3 铁律 4）。

---

## 8. 禁止事项

1. 禁止 `nginx -s reload` / `systemctl restart nginx` —— 纯静态替换不需要（改 vhost 才 reload，那是另案）。
2. 禁止改 `agentmp.conf`（`2e8fbc15…`）；确需改时走另案授权，不在本规程内。
3. 禁止把 MP_verify 两枚移进 `dist` 或删除 —— 移走即微信域名校验失效。
4. 禁止把任何凭据文件放进 web root（唯一合法位置 `/data/apps/agent-mp-cred/`，700/600）。
5. 禁止清理 dist 内旧的 `umi.65bb8d50.js` / `umi.730fc955.css` —— 回滚材料＋旧缓存页存活依赖。
6. 禁止 dev / test 构建产物上生产（`PROFILE` 必须 `prod`，见 `SOP-00 §6.3`）。
7. 禁止用 HTTP 状态码 `200` 定性泄漏 —— SPA 兜底使一切未知路径返回 200，必须内容级鉴别（判例一）。
8. 禁止只凭"served 同锚"判定路由/布局类改动通过（判例二）。
9. 禁止在未取到新 index 的情况下判"修复未生效"（判例三）。
10. 禁止删除 `dist.pre-*` 备份（用户确认前）；禁止顺手清理历史 `dist-bak-g7-20261121`。
11. 禁止把测试机 compose/nginx 形态当生产事实引用（fail-closed）。

---

## 9. 收尾

1. 证据归档 `变更留痕/<日期>-G7-<批次>-agent-mp-web/`（或按批次命名），含：前置十项读数、备份坐标与 sha、
   `sha256sum -c` 输出、三路判据原始输出、外部响应头。
2. `anchors/agent-mp.env`：CURRENT 移入 ROLLBACK、新值写入 CURRENT（**同一提交内**）。
3. `变更留痕/00-索引.md` §1「生产现役速查」同步更新该行。
4. `dist-staging-*` 清理；`dist.failed-*` 留待归因后按授权清理。
5. Hub STATE 留痕一行。

---

## 10. 立本规程的四条判例（全部为已发生的真事故，不是假设）

**判例一 · SPA 兜底会伪造"泄漏"**：`try_files` 使任何未知路径返回 `200 ＋ index.html`。G6 机内验收首跑
"凭据路径"返 `200`（期望 `404`），当场被判为"真缺陷"；字节级鉴别后定性为 `SPA_FALLBACK_INDEX_NOT_CRED`（body＝index，**无泄漏**）。
→ **暴露面判据一律内容级**（body sha ≠ 敏感件 sha）；`404` 页与 `index` 均属合法拒绝形态。
另：凭据交付件因此从 `/data/apps/agent-mp/` 迁出到 `/data/apps/agent-mp-cred/`（700/600），做防御纵深。

**判例二 · HTTP 级同锚 ≠ 运行期正确**：G6 全部 HTTP 判据通过（served 三件同锚、health OK、SPA 兜底成立），
但 B 端路由被 C 端授权壳吞掉：微信外跳"请在微信客户端打开链接"，微信内空白页。
SPA 的路由/布局缺陷**只在 JS 执行期暴露**。
→ 凡路由/布局/构建配置类改动，**必须**加 §6.3 运行期实测。

**判例三 · 浏览器缓存会掩盖发布**：G7 修复后首次浏览器实测，加载的仍是旧 bundle `umi.65bb8d50`
（即 G6 的产物），若据此定性会误判"修复未生效、回去改代码"。
→ 正解：外部 `curl` 实读 served 锚 ＋ 带 `?v=` 强制取新 index 后再测。

**判例四 · 管道喂脚本时 ssh 会吞 stdin**：`tr -d '\r' < x.sh | bash` 中首次 ssh 调用吃掉后续脚本行，
表现为"执行到一半静默中断"。
→ 凡此类脚本，ssh 一律加 `-n`。
