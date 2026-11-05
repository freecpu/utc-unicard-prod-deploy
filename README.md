# utc-unicard-prod-deploy — 生产部署操作仓

本仓是 **UTC / unicard 生产环境的部署操作与取证仓**，不是应用代码仓。
它承载三类东西：**可复跑的探针脚本**、**逐次变更的原始证据**、**给操作者照抄的 SOP**。

> 本仓刻意与 `utc-unicard-test-deploy`（测试环境总控）分开：
> 生产与测试的路径体系、systemd 单元名、配置注入形态都**不可互套**，
> 混在一个仓里迟早会有人把测试机的命令贴到生产上。

---

## 1. 仓库结构

```
utc-unicard-prod-deploy/
├── README.md              ← 本文件
├── 归属矩阵.md             ← 谁负责什么、哪台机器归谁操作、授权边界
├── 指纹台账.md             ← jar / unit / 外置配置的 sha256 权威记录（回滚判据）
├── .gitignore
├── sop/
│   ├── SOP-00-构建规范.md          ← 产物怎么来、命名与指纹怎么记
│   ├── SOP-01-utc-admin-生产换包.md ← 换 jar 的逐步操作 + 判据 + 回滚
│   └── SOP-02-threeants-配置注入.md ← -D 注入的逐步操作 + 判据 + 回滚
├── scripts/               ← 全部只读探针与验证脚本（可复跑）
└── 变更留痕/               ← 每次变更一个目录，内含原始输出与验证记录
```

## 2. 机器与单元速查

| 角色 | SSH 别名 | 主机 | systemd 单元 | 端口 |
|---|---|---|---|---|
| 生产 UTC | `runyd-47-96-163-197` | 47.96.163.197:62211 (user `runyd`) | `ryd-utc-admin.service` | 8001（context-path `/manage`） |
| 生产 threeants | `runyd-47-111-157-5` | 47.111.157.5:62211 (user `runyd`) | `ryd-unicard-official.service` | 7003 |
| 测试机 threeants | `47.97.47.23` | 47.97.47.23:22 (user `root`) | `unicard-test-threeants-official.service` | 7003 |

**生产两台都必须走 SSH 别名**（端口 62211、用户 runyd）。直连 IP 的 22 端口会超时。

两台生产机的 systemd 都是 **219**（CentOS 7），实测差异见 SOP 里的「环境差异」段：
`systemctl show -p KEY --value` 不支持、`NRestarts` 属性不存在、
`StartLimitIntervalUSec` 叫 `StartLimitInterval`。**脚本一律用 `-p KEY | cut -d= -f2`。**

## 3. 三条铁律

1. **生产默认只读。** 任何写操作（改 unit、换 jar、重启服务、删文件）都必须先取得
   用户对该**具体动作**的显式授权。授权不按机器给，按动作给。
2. **判据不能只看进程活着。** `Type=simple` + `Restart=` 下 systemd 在 exec 成功那一刻
   就记 `active`，之后应用绑定失败、JVM 退出、再拉起，`is-active` 会在 active/activating 间跳，
   **恒定不可作健康判据**。硬信号只有两个：**端口 LISTEN**、**日志里点名的属性名**。
3. **0 命中不可当否定结论。** 空结果比错误结果更危险 —— 两边都空会得出「相同」的假阳性。
   本仓所有比对脚本都带空结果 FATAL 守卫；告警类脚本必须带正控 selftest
   （`scripts/audit-tmp-creds.sh` 就是被 selftest 抓出过真缺陷的）。

## 4. 脚本清单

| 脚本 | 用途 | 读/写 |
|---|---|---|
| `probe-utc-http.sh` | UTC 12 探针 HTTP 基础回归（换包前后各跑一次做 diff） | 只读 |
| `probe-utc-runtime.sh` | UTC 运行态取证（jar 指纹、PID、端口、启动时刻） | 只读 |
| `probe-utc-traffic.sh` | UTC 流量/调用方观测 | 只读 |
| `compare-utc-http.sh` | 两次 HTTP 探针结果的 diff | 只读 |
| `analyze-error-delta.sh` | 换包后 error 日志增量归因 | 只读 |
| `error-noise-rate.sh` | error 日志噪声率基线（判断增量是否属既有噪声） | 只读 |
| `probe-threeants-config.sh` | threeants 配置形态取证（unit、cmdline、yml 搜索路径） | 只读 |
| `probe-prod-portability.sh` | **搬到生产前必跑**：systemd 版本 / journal 是否有内容 / `/proc` 权限 / Restart 策略 | 只读 |
| `verify-d-injection.sh` | `-D` 注入通路五模式验证（neg/neg2/neg3/pos/restore） | **写**（改 unit + 重启） |
| `compare-jar-manifest.sh` | jar 外层 (长度,CRC-32,条目名) 全清单指纹 | 只读 |
| `inspect-jar-manifest.sh` | 清单**判别力**自检（防「清单相同但覆盖不到关心对象」） | 只读 |
| `compare-nested-jar.sh` | 递归下钻嵌套模块 jar + pom 归一化哈希 | 只读 |
| `compare-jar-class.sh` | 单 class 比对（已被 manifest 方案取代，保留备查） | 只读 |
| `run-jar-cmp.sh` | 从 unit 解析 jar 路径的薄封装（含相对路径处理） | 只读 |
| `read-prod-agentflow.sh` | 只读查询生产 `t_agent_flow`（凭据不回显、不落盘） | 只读 |
| `audit-tmp-creds.sh` | 明文凭据审计（5 级分类 + selftest 正控/负控）；**提交前门禁** | 只读 |
| `diag-cred-shape.sh` | 掩码查看凭据命中上下文（用于人工复核误报） | 只读 |
| `watch-cline.sh` | C 线事件观察（退卡/周期更新） | 只读 |

## 5. 提交纪律

- `git add` 前先 `git status --short` 核对清单，只提交本次任务相关文件。
- **提交前必须跑凭据门禁**：
  ```bash
  bash scripts/audit-tmp-creds.sh selftest          # 先证明工具不是瞎的
  AUDIT_DEPTH=99 bash scripts/audit-tmp-creds.sh .  # 再扫全树，HARDCODED 必须为 0
  ```
  selftest 不过时，`CLEAN` 结论**无效**（可能是假阴性）。
- 证据文件里只允许出现**长度与哈希**，不允许出现凭据正文。
  已归档的取证输出里，凭据一律以 `REDACTED` 或 `username_len = 4  password_len = 11`
  这类形态留存。
- 远程命令**不内联**：含 `$`、竖线、空格、中文的一律写成脚本 `scp` 上传执行。
  PowerShell 会本地求值 `$()`、吃掉 awk 的 `$N`、把 `\$f` 展开成 Windows 路径。

## 6. 当前未闭环事项

见 `指纹台账.md` 末尾的「技术债与未闭环」段，以及 `变更留痕/` 下各次变更的验证记录。
其中**优先级最高**的一条：生产 threeants 预划拨 fail-closed（自 2026-10-28 起，现役缺陷），
修复通路已验证可用，等待方案选型与重启授权 —— 见
`变更留痕/20261105-S4-D注入通路验证/验证记录.md` §10。
