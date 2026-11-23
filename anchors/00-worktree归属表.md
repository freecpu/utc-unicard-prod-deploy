# anchors/00-worktree归属表 — 一个 worktree = 一个项目 = 一个部署单元

> **建立** 2026-11-23 ｜ **依据** 用户裁定：「不同的 worktree，当成单独项目，提交自己的分支」
> **立表原因**：`unicard-official-nodejs` **一个 git 仓派生出三个 worktree**，其中两个有生产部署单元。
> 按仓名下结论会把三个项目混成一件事 —— 2026-11-23 已**实际发生一次**（主管帽误判为「两个独立前端仓」，
> 进而得出「两仓都要先推」的错误结论）。本表是防止该错误复发的唯一入口。
>
> ★ **铁律：一个 worktree 对应一个锚，不得一对多、不得多对一。**
> ★ 本表只登记归属，不代替 `anchors/<project>.env`。锚值以各自 `.env` 为准。

核实命令（三个 worktree 共享同一个 `.git`，任一处执行结果相同）：

```bash
git -C <任一 worktree 目录> worktree list
git -C <任一 worktree 目录> rev-parse --git-common-dir
```

---

## 1. 前端三 worktree（同一仓 `unicard-official-nodejs`）

| # | worktree 目录 | 分支 | HEAD（11-23） | 部署单元 | 锚文件 | 目标机 / 静态根 |
|---|---|---|---|---|---|---|
| **W1** | `hhrgit/unicard-official-nodejs` | `feature/1.2.0-threeants` | `05724b5` | **G4** official-web | `anchors/official-web.env` | threeants `runyd-47-111-157-5` ／ `/usr/local/ryd-unicard/bin/dist` |
| **W2** | `hhrgit/unicard-agent-mp-nodejs` | `feature/agent-mp` | `7747178` | **G6/G7** agent-mp 前端 | `anchors/agent-mp.env` | `runyd-223-4-12-235` ／ `/data/apps/agent-mp/dist` |
| **W3** | `hhrgit/unicard-nlxq` | `feat/deps-migration` | `869a561` | **无部署单元** | 无 | — |

### W3 为何不纳入（用户 2026-11-23 裁定：不纳入，只登记说明）

1. 它是**前端原主线（H5）**，生产侧已由 W1（threeants 变体）/ W2（agent-mp 变体）两个 worktree 覆盖；
2. HEAD 停在 **2026-08-14**，分支性质是依赖迁移（antd 私有依赖转 freecpu 镜像），非业务开发；
3. 有 2 个未提交改动（`src/pages/iccid/$id.tsx`、`src/pages/recharge/iccid.tsx`），`dist` 停在 2026-09-08，均与生产无关。

★ 但**不得据此假定它不存在** —— 将来若启用，须先补生产坐标与 ROLLBACK 材料，再单独建锚。

---

## 2. 独立仓（不是 worktree，单列以防混入上表）

| 目录 | 分支 | HEAD | 部署单元 | 锚文件 | 目标机 / 静态根 |
|---|---|---|---|---|---|
| `utc/utc-admin-web` | `master` | `dcf86e0` | **G2** admin-web | `anchors/admin-web.env` | UTC `runyd-47-96-163-197` ／ `/data/html/ryd-utc-admin/dist` |

后端三项（`utc/utc-server`→G1、`hhrgit/unicard-java-threeants`→G3、`utc/xxl-job-admin`→G8）不属前端，
各自锚文件已含源坐标，不在本表重复。

---

## 3. 推送纪律（★ W1 有误推供应商的实质风险）

两个 remote 性质完全不同：

| remote | 地址 | 性质 |
|---|---|---|
| `mine` | `github.com/freecpu/unicard-official-nodejs.git` | **自有镜像，唯一推送目标** |
| `origin` | `github.com/hhr227/unicard-official-nodejs.git` | **供应商上游，禁止推送** |

★ **实测陷阱**：W1 的 `feature/1.2.0-threeants` 的 **upstream 指向 `origin`**（`git branch -vv` 显示 `ahead 18`）。
在该 worktree 里敲裸 `git push`，默认会把 **18 个自有业务提交推给供应商仓**。这是不可逆事故。
→ **一律显式写 `git push mine <branch>`，永不依赖 tracking。**
→ 根治建议（需单独授权，改的是本地 git 配置）：`git branch --set-upstream-to=mine/feature/1.2.0-threeants`。

---

## 4. 各自的推送现状（2026-11-23 实测）

| 项目 | 本地 HEAD | `mine` 上最新 | 差 | 待执行 |
|---|---|---|---|---|
| **W1** official-web | `05724b5`（11-23 20:03 滚动修复） | `3b447a0`（11-16 16:28） | **1** | `git push mine feature/1.2.0-threeants` |
| **W2** agent-mp | `7747178`（11-23 20:03 `.middle` 容器） | `7e96341`（11-21 21:39 G7） | **1** | `git push -u mine feature/agent-mp` |
| **W3** nlxq | `869a561` | `869a561` | 0 | 已同步，不动作 |
| G2 admin-web | `dcf86e0` | 已同步（`origin/master`） | 0 | 不动作 |

★ **修正一处既有误判**：此前记「official-web 有 10 个未推送提交」是 `Select-Object -First 10` 截断造成的错觉。
真实为：相对 `mine` **ahead 1**；相对 `origin` ahead 18（长期分叉，**不是待推事项**）。

---

## 5. 构建产物落点（每项目独立，互不覆盖）

| 项目 | 构建命令 | 产物落点 | 现有 dist 的身份 |
|---|---|---|---|
| **W1** official-web | `npm run build`（= `cross-env UMI_ENV=prod umi build`） | `dist-<7位commit>/` | `dist/` **＝ G4 生产现役逐字节副本**（11-16），**是回滚比对物证** |
| **W2** agent-mp | 同上 | `dist-<7位commit>/` | `dist/` **＝ G7 生产现役逐字节副本**（11-21），**是回滚比对物证** |
| **W3** nlxq | 同上 | 不涉及 | 停在 2026-09-08，与生产无关 |
| **G2** admin-web | `npm run build`（= `vue-tsc --noEmit && vite build`） | `dist-<7位commit>/` | 已有 `dist-b2-dcf86e0`（对应 HEAD）＋ `dist-b2-base`（＝ G2 现役副本） |

★ **R-BUILD-3 的直接后果**：W1/W2 的 `dist/` 现在是「生产现役」的唯一本地副本。
**在 `dist/` 里原地 build 会把它覆盖掉** → 构建前必须先改名保留（如 `mv dist dist-keep-20261123`），
构建输出再改名到 `dist-<7位commit>/`。这不是洁癖，是保住回滚比对的唯一物证。

---

## 6. 未提交依赖漂移（W2 专属，**禁止提交**）

W2 工作区有 3 个 tracked 改动：

```
package.json        |     4 +-
package-lock.json   | 13696 ++++++++++++++++++++++++++++++++--
yarn.lock           | 19957 ++++++++++++++++++++----------------
```

内容是本地依赖替换：

```diff
-    "antd": "git+ssh://git@github.com/hhr227/ant-design.git#4.6.5-1",
-    "antd-mobile": "git+ssh://git@github.com/hhr227/ant-design-mobile.git#2.3.4-1",
+    "antd": "file:../ant-design",
+    "antd-mobile": "file:../ant-design-mobile",
```

★ **这三件绝不能提交到 `feature/agent-mp`**：一旦提交，任何人 clone 都会因 `../ant-design` 不存在而构建失败。
它们是**本地构建的临时手段**，不是代码改动。

处置：
1. 构建期间保持原样（`node_modules` 已按此装好，构建只读 `node_modules`）；
2. **构建完成后立即还原**：`git checkout -- package.json package-lock.json yarn.lock`；
3. 若构建出的产物要与历史产物做同源比对，须在 `BUILD-INFO` 记明「antd 来自本地 `file:../ant-design`」，
   否则同锚比对会因依赖来源不同而失败，且无法解释。

---

## 7. 维护规则

1. 新增/删除 worktree → 同一次提交内更新本表。
2. 锚文件新增 → 必须在本表登记，否则视为未建档。
3. 本表与 `git worktree list` 实测不一致时，**以实测为准**并立即修表。
4. 本表只写归属与纪律，**不写锚值**（锚值唯一源＝`anchors/<project>.env`，避免两处日后分叉）。
