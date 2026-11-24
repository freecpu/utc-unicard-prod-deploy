# SOP-04：静态 dist 生产替换（S2 admin-web ＋ S4 official-web）

- 版本：v1.0（2026-11-18）
- 授权来源：REQ-20261113-01《M5 生产上线批次计划》v1.0 §三 D2。
  **编写不需授权；admin-web 替换＝G2（前置 G1 通过）、official-web 替换＝G4（★硬前置＝G3 实证非空 statusDesc 且经主管核验），逐次显式授权。**
- 执行分工：默认＝主管出命令，用户在生产机执行。
- 共同性质：纯静态文件替换，**零服务重启、零 nginx reload**（root 路径不变，nginx 按请求读盘）。
  严禁顺手 `nginx -s reload` / restart openresty——那会波及同机全部 vhost。

---

## 0. 通用流程与交付件口径（三套前端共用；2026-11-23 新增）

> 本节是 A／B 两节共有的骨架，A／B 只写各自差异。**两者冲突时以本节为准**（差异已逐条标注）。
> 立本节的直接原因：同一套「备份 → 上传 → 校验 → 切换 → 判据 → 回滚」在 A、B 里各写了一遍，
> 2026-11-23 为 agent-mp 写第三遍（`SOP-07`）时，三份表述已经出现分歧（切换手法、备份落点、旧资源处理各不相同）。
> **重复三次以上的流程必须提成一处，否则第四次一定写错一处。**

### 0.1 交付件从哪来（★ 定源口径，2026-11-23 起）

| 项 | 规定 |
|---|---|
| 谁生成 | **源码仓负责会话**，按 `SOP-00 §6` 产出三件套：`dist-<7位短commit>/` ＋ `BUILD-INFO` ＋ `SHA256SUMS.txt` |
| 必须满足 | `PROFILE=prod`；目录名短 commit 与 `COMMIT` 一致；`sha256sum -c` 全 OK |
| 部署侧只做 | 准入校验（形态／清单／`PROFILE`／COMMIT 一致性）。**不构建**（R-BUILD-1） |
| 一律拒收 | dev／test 构建产物；从测试机在役目录“拉回”的件；只有源码或只有 commit 号 |

### 0.2 两条历史定源口径作废（历史行保留不删）

1. **A1（admin-web）「测试部署仓 `web/dist/utc-admin/` 提取」** —— 产物本身是 Vite 生产构建、形态合法，
   但**没有 BUILD-INFO、没有 commit 绑定**，无法证明它对应哪个源码提交。今后按 §0.1。**G2 已执行的事实不回改。**
2. **B1（official-web）「测试机在役 dist 原字节拉回」** —— **作废**。测试机 threeants 跑的是 `UMI_ENV=dev` 产物（含 `TEST_OPENID`），
   而《前端部署规范》§二明令 dev 产物严禁上生产，两条口径直接矛盾。今后按 §0.1 由源码仓生产构建。
   **G4 已上线的产物不回改（既成事实），但它是最后一份这类产物，不得成为先例。**

> **★ 2026-11-24 勘误（自纠 74）**：上面第 2 条的**理由**失据 —— 实测**生产现役** G4（`umi.dc9bce91.js`）与 G6
> （`umi.8f0720bb.js`）包内**各含 `TEST_OPENID` 2 次**，即“含 `TEST_OPENID`”并不能区分 dev 产物与生产产物。
> 结论（定源口径作废、今后按 §0.1）**不变**，但真正的理由是：**无法证明它对应哪个源码 commit**（无 BUILD-INFO、无 commit 绑定）。
> 今后做准入判定**不得再用 `TEST_OPENID` 命中作为 dev 证据**；判据只认 `BUILD-INFO` 的 `PROFILE`／`COMMIT`
> 与目录名短 commit 三者一致，外加清单 `sha256sum -c`。

### 0.3 五步骨架

| 步 | 动作 | 硬约束 |
|---|---|---|
| 1 前置 | 现役锚逐字核对 → 磁盘余量 → 依赖方后端健康 | 锚不等＝停手查清，不“大概一致” |
| 2 备份 | 同分区 `cp -a`，命名 `dist.pre-<批次>-<YYYYMMDD>` | 备份 index 的 sha 必须 == 现役锚；**未备份成功绝不切换** |
| 3 上传 | `scp` 到**同分区** staging（与被替换目录同级） | 跨分区 `mv` 不原子 |
| 4 切换 | 校验 → 旧 hash 资源并留 → 双 `mv`（A/B）／原地覆盖（SOP-07） | 旧资源必须并留；HTML 无 Cache-Control 时缓存期长 |
| 5 判据 | served 锚一致 → 功能 → 零波及（nginx 与同机邻居） | 判据不全等于没做完 |
| 回滚 | 备份目录恢复 → sha 回现役值 | **不重启任何服务** |

### 0.4 三套前端的差异（只列会改变命令的部分）

| 维度 | admin-web（§A） | official-web（§B） | agent-mp（`SOP-07`） |
|---|---|---|---|
| 形态 | Vite `assets/index.<hash>.js` | umi 根级 `umi.<hash>.js` | umi 根级（同 §B） |
| 静态根 | `/data/html/ryd-utc-admin/dist` | `/usr/local/ryd-unicard/bin/dist` | `/data/apps/agent-mp/dist` |
| 备份落点 | 同目录 | **必须落 `/data`**（根分区 94% 满） | 同目录（`/data` 下） |
| 机器属性 | 共享机（多 vhost） | 共享机（5 个 java 邻居） | **独占机** |
| 切换手法 | 旧资源并留＋双 `mv` | 同 §A | 原地覆盖（旧 umi 件保留） |
| SPA 兜底 | 无记录 | 无记录 | **有** → 暴露面判据须内容级 |

### 0.5 「旧资源并留」为什么是强制的

替换只改 `index.html` 与新增 hash 件，但**旧 `index.html` 可能仍在用户浏览器／微信 X5 的缓存里**，
它引用的还是旧 hash 的 js/css。旧资源一并保留，缓存期内的旧页面才不会 404 或白屏。
代价是目录里同时存在多代 hash 文件 —— **这是预期形态，不是残留垃圾，不得清理**（`SOP-07` 的 `umi.65bb8d50.js` 同理）。

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
   ★ 2026-11-18 已核验（台账 §21）：交付件＝测试部署仓 origin/main `web/dist/utc-admin/` 提取 65 文件，与测试机在役逐文件 ZERO_DIFF；
   index=`5daccd9d…a03cd6`（685 B）引 assets/index.05463381.js；staging＝Hub var/tmp/s0-artifacts/web/dist/utc-admin/。
   ★ 2026-11-23 定源口径作废：本条「从测试部署仓提取」也没有 BUILD-INFO 与 commit 绑定，无法证明产物对应哪个源码提交。
     今后按 §0.1 由源码仓产出三件套；上面这行只是 G2 当时的实操记录，不再作为 G2 类替换的做法依据。
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
   ★ 2026-11-18 定源更正（台账 §21）：git 登记件 css 与测试机在役脱节（同字节数不同内容）且多一件历史 js，
   **G4 交付件＝测试机在役 dist 原字节 tar 拉回件**（5 文件 ZERO_DIFF 复核；staging＝Hub var/tmp/s0-artifacts/machine-threeants/），
   锚：index=`31670ccf…70ce90`（483 B）／umi.dc9bce91.js=`6c19b635…2fdb7b`（1,597,309 B）／umi.b7afafd6.css=`01cc3e93…9734b2`（与 B0 现役 css 同锚＝样式零变更）／static 两件；
   严禁改用 git 登记件（未经运行期验收）；git 登记脱节修复另案。
   ★★ 2026-11-23 裁定：**「测试机在役 dist 原字节拉回」这条定源口径作废**（见 §0.2 第 2 条）。
    理由：测试机 threeants 跑的是 `UMI_ENV=dev` 产物（含 `TEST_OPENID`），与《前端部署规范》§二「dev 产物严禁上生产」直接矛盾。
    今后按 §0.1 由源码仓 `PROFILE=prod` 构建。G4 已上线的产物不回改（既成事实），但不得成为先例。
    本条上句「严禁改用 git 登记件」的结论仍有效（未经运行期验收的东西不能直接上生产）。
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
   > ★ 分界（2026-11-23 补）：本条的前提是**共享机**。agent-mp 的第四台机是**独占机**（`sites-enabled` 只有一个承载本栈的 symlink），
   > 改 vhost 时 reload 合法且必要；但**纯静态 dist 替换依旧不需要 reload**。见 `SOP-07` 开头的分界说明。
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