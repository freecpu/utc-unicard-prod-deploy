# SOP-04：静态 dist 生产替换（S2 admin-web ＋ S4 official-web）

- 版本：v1.0（2026-11-18）
- 授权来源：REQ-20261113-01《M5 生产上线批次计划》v1.0 §三 D2。
  **编写不需授权；admin-web 替换＝G2（前置 G1 通过）、official-web 替换＝G4（★硬前置＝G3 实证非空 statusDesc 且经主管核验），逐次显式授权。**
- 执行分工：默认＝主管出命令，用户在生产机执行。
- 共同性质：纯静态文件替换，**零服务重启、零 nginx reload**（root 路径不变，nginx 按请求读盘）。
  严禁顺手 `nginx -s reload` / restart openresty——那会波及同机全部 vhost。

---

## A. admin-web（S2，UTC 机，Vite 形态）→ G2

### A0. 坐标与回滚锚（R0/R1 实测 2026-11-18，台账 §11/§16）

- 机：ssh 别名 `runyd-47-96-163-197`；openresty/1.19.9.1，vhost `servers/ryd-utc.conf`（listen 8000，utc.nlxq.net）
- 静态根：`/data/html/ryd-utc-admin/dist`（属主 nlxq:nlxq）；磁盘 /data 余 184G
- 现役锚：
  | 文件 | sha256 | 字节 |
  |---|---|---|
  | index.html | `d9ef7d95dd29fb6611e1904c9cdd9b8217c3b684ccf050fa9037f2428170f6e7` | 685 |
  | assets/index.508ff2fc.js | `e6a04f933c5925ab4be359741b7f93ed18dc00bcd858dfcb81505d7c609c24dd` | 1,386,131 |
  | assets/index.293e09e1.css | `293e09e129cfcdad9dcb6f1dd13e88871a0e0ff548b92abfba17efcfdd9734b2` | 411,184 |
- 备份惯例：同目录 `dist.bak` / `dist.20261026.bak` / `dist.zip`（本次沿用 `dist.pre-G2-<日期>`）

### A1. 前置（只读）

1. index.html 与两件 assets sha 对 A0 逐字（不等＝漂移，停手查清）。
2. 新 dist（S2 交付件）：本地构建产物为 **Vite 形态**（assets/index.<hash>.js），sha256 清单已登记；
   **严禁 dev 构建产物上生产**（前端部署规范 §二红线）。
3. G1（utc-admin jar）已通过且 12 探针 after 全绿——前端新字典依赖后端 statusDesc 键。

### A2. 备份（★ 回滚唯一来源）

```bash
ssh runyd-47-96-163-197 'cp -a /data/html/ryd-utc-admin/dist \
  /data/html/ryd-utc-admin/dist.pre-G2-<日期> && \
  sha256sum /data/html/ryd-utc-admin/dist.pre-G2-<日期>/index.html'
```

备份 index.html sha 必须 = A0 值。备份在用户确认前严禁删除。

### A3. 替换（目录级原子切换＋旧 assets 并留）

★ 缓存风险：浏览器可能缓存旧 index.html，替换后仍按旧 hash 名请求 js/css。
**新 dist 就位前先把旧 assets 并入新包**（hash 文件名天然不冲突），旧页面在缓存期内不 404：

```bash
# 本地：新 dist 上传为兄弟目录（同分区 /data，目录 rename 原子）
scp -r <新dist本地路径> runyd-47-96-163-197:/data/html/ryd-utc-admin/dist.new

ssh runyd-47-96-163-197 'cp -an /data/html/ryd-utc-admin/dist/assets/. \
  /data/html/ryd-utc-admin/dist.new/assets/ && \
  sha256sum /data/html/ryd-utc-admin/dist.new/index.html && \
  mv /data/html/ryd-utc-admin/dist /data/html/ryd-utc-admin/dist.old-G2 && \
  mv /data/html/ryd-utc-admin/dist.new /data/html/ryd-utc-admin/dist && \
  ls -ld /data/html/ryd-utc-admin/dist'
```

- `cp -an`：只补缺不覆盖（新包同名文件优先）。
- 两次 `mv` 之间理论上有毫秒级空窗；admin-web 为内部管理端，可接受；如要求零空窗改用 symlink 切换（须先确认 vhost root 是否解引用，本次不改 vhost，故用双 mv）。
- 属主保持 nlxq:nlxq（scp 登录用户即 nlxq 则天然一致，复核）。
- `dist.old-G2` 暂留，G2 核验通过收尾时再清理（备份 `dist.pre-G2-*` 长期保留）。

### A4. 判据（替换后立即）

| # | 判据 | 通过条件 |
|---|---|---|
| ① | `curl -s http://127.0.0.1:8000/ -H "Host: utc.nlxq.net"` 的 sha256 | = 新 index.html 登记值 |
| ② | 新 index 引用的 js/css 两件 `curl -o /dev/null -w "%{http_code}"` | 均 200，sha = 交付清单 |
| ③ | 旧 hash 两件（A0 表）仍 200 | 旧缓存页面不 404 |
| ④ | 用户浏览器强刷（Ctrl+F5）登录 admin | 卡状态列显示中文 statusDesc（G1 后端已供键） |
| ⑤ | nginx 零动作 | 未 reload/restart，其他 vhost（8002 sp 等）不受影响 |

### A5. 回滚（G2 判据不过）

```bash
ssh runyd-47-96-163-197 'mv /data/html/ryd-utc-admin/dist /data/html/ryd-utc-admin/dist.failed-G2 && \
  cp -a /data/html/ryd-utc-admin/dist.pre-G2-<日期> /data/html/ryd-utc-admin/dist && \
  sha256sum /data/html/ryd-utc-admin/dist/index.html'
```

sha 回到 A0 值（逐字）；失败现场 `dist.failed-G2` 保留供归因。回滚不需重启任何服务。

---

## B. official-web（S4，threeants 机，umi 形态）→ G4

### B0. 坐标与回滚锚（R0c 实测，台账 §12/§16）

- 机：ssh 别名 `runyd-47-111-157-5`；nginx/1.7.4，vhost `servers/threeantsonline.nlxq.net.conf`（listen 443）
- 静态根：`/usr/local/ryd-unicard/bin/dist/`（属主 nlxq:nlxq）；`/api/web/` → upstream **127.0.0.1:7003**
- ★ 根分区 94% 满仅 1.3G：新 dist ≈2MB 可容，但**备份一律落 /data**（与 SOP-03 同纪律）
- 现役锚：
  | 文件 | sha256 | 字节 |
  |---|---|---|
  | index.html | `4e9f978d785f235ab20ce9a5e4f9ac284d242d4a586d68241958035ef94c9c06` | 483 |
  | umi.8376da82.js | `892f37496815e69294e80f42d2ccb1f4a7aaa3fbbe500892a64b27c0ede4d746` | 1,596,941 |
  | umi.b7afafd6.css | `01cc3e9371ca3bf9d9f7f3b342212edd74072a09784314c3b494f652520e2b01` | 402,044 |
- 备份惯例：`bin/dist.bak`、`dist20260928`、`dist20261027`、`dist.zip`（历史件不动）

### B1. 前置（只读＋硬门禁）

1. **★G4 硬前置**：G3 已通过，且 `probe-statusdesc.sh` 实证 7003 返回**非空 statusDesc**、经主管核验。未实证严禁启 G4。
2. index.html 与 umi 两件 sha 对 B0 逐字。
3. 新 dist（S4 交付件）为 **umi 形态**（umi.<hash>.js），生产构建（严禁 dev 产物），sha 清单已登记。
4. `df -h /` 复核 ≥ 100MB（staging ≈2MB＋余量）。

### B2. 备份（落 /data）

```bash
ssh runyd-47-111-157-5 'sudo mkdir -p /data/log-archive/ryd-unicard && \
  cp -a /usr/local/ryd-unicard/bin/dist /data/log-archive/ryd-unicard/dist.pre-G4-<日期> && \
  sha256sum /data/log-archive/ryd-unicard/dist.pre-G4-<日期>/index.html'
```

### B3. 替换（同 A3 模式：staging 兄弟目录＋旧资源并留＋双 mv）

```bash
scp -r <新dist本地路径> runyd-47-111-157-5:/usr/local/ryd-unicard/bin/dist.new

ssh runyd-47-111-157-5 'cp -an /usr/local/ryd-unicard/bin/dist/. \
  /usr/local/ryd-unicard/bin/dist.new/ && \
  sha256sum /usr/local/ryd-unicard/bin/dist.new/index.html && \
  mv /usr/local/ryd-unicard/bin/dist /usr/local/ryd-unicard/bin/dist.old-G4 && \
  mv /usr/local/ryd-unicard/bin/dist.new /usr/local/ryd-unicard/bin/dist && \
  ls -ld /usr/local/ryd-unicard/bin/dist'
```

- umi 形态旧资源含 umi.js/umi.css 及静态图片，`cp -an` 整目录并留（不只 assets）。
- ★ C 端用户量大、缓存期长：旧资源并留是**强制**的，不得跳过。
- ★ X5 缓存红线（已核实口径）：生产 nginx 对 HTML **未设 Cache-Control**（只有 ETag/Last-Modified），
  走启发式缓存，微信 X5 内核下可能久缓存 index.html；js/css 带 hash 可长缓存。
  故替换后部分用户仍持旧 index：旧资源并留保存期不白屏；新形态生效验证以强刷/新会话为准，
  不得因「部分用户仍旧页」判 G4 失败，也不得为此改 vhost 加缓存头（那是另案变更）。
- 同分区（bin/ 下）双 mv；严禁把 staging 放 /data 再跨分区 mv。

### B4. 判据

| # | 判据 | 通过条件 |
|---|---|---|
| ① | `curl -sk https://127.0.0.1/ -H "Host: threeantsonline.nlxq.net"` sha256 | = 新 index.html 登记值 |
| ② | 新 umi.<hash>.js/css `curl -sk -o /dev/null -w "%{http_code}"` | 均 200，sha = 交付清单 |
| ③ | 旧 umi.8376da82.js / umi.b7afafd6.css 仍 200 | 旧缓存页面不白屏 |
| ④ | `/api/web/` 反代仍指 7003 | vhost 零改动（sha 复核 conf 不变） |
| ⑤ | 用户浏览器强刷 C 端卡详情 | 状态 9 显示「预清除」等中文，无 UNKNOWN 兜底异常 |
| ⑥ | nginx 零动作、同机 5 个 java 服务零波及 | 未 reload/restart 任何服务 |

### B5. 回滚

```bash
ssh runyd-47-111-157-5 'mv /usr/local/ryd-unicard/bin/dist /usr/local/ryd-unicard/bin/dist.failed-G4 && \
  cp -a /data/log-archive/ryd-unicard/dist.pre-G4-<日期> /usr/local/ryd-unicard/bin/dist && \
  sha256sum /usr/local/ryd-unicard/bin/dist/index.html'
```

sha 回到 B0 值；跨分区 cp ≈2MB 秒级，可接受。失败现场保留。

---

## C. 共同禁止事项

1. 禁止 nginx reload/restart（静态替换不需要；reload 波及同机全部 vhost）。
2. 禁止改任何 vhost conf。
3. 禁止 dev 构建产物上生产。
4. 禁止跳过旧资源并留（缓存期旧 index 请求旧 hash 资源会 404/白屏）。
5. 禁止 sha 未核对就切换；禁止删除备份（用户确认前）。
6. 禁止 G4 先于 G3 实证 statusDesc（链内序物理依据：/api/web/ → 7003）。
7. threeants 机禁止把备份/staging 大件落根分区（94% 满）。
8. 禁止顺手清理历史备份目录（dist.bak/dist20260928 等）。

## D. 收尾（各自 G 通过后）

1. 证据归档 `变更留痕/<日期>-G2-admin-web换包/`、`<日期>-G4-official-web换包/`。
2. 台账更新：dist 新锚（index/主 js/主 css sha＋字节＋mtime）、备份坐标；历史行不改，新节登记。
3. `dist.old-G2` / `dist.old-G4` 在核验通过且用户确认后清理；`pre-G*` 备份保留。
4. Hub STATE 留痕一行。