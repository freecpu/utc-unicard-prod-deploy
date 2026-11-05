# audit-pii.ps1 — 个人数据（PII）入库闸门
#
# 为什么需要这个工具（2026-11-05 S9 实测事故）：
#   ① 生产 error 日志正文含 iccid 与 openId（CellSafetyClient 把整个请求体打进日志）；
#      我取样时用 `tr '0-9' '#'` 掩码，**只掩数字、残留字母**，openId 是字母型假名化标识
#      → 等于没掩，且归档已推送 GitHub。
#   ② 事后全仓核查时，第一次内联测量报出 ICCID=161 / MSISDN=57，**全是假阳性**：
#      无边界正则在 sha256 十六进制串内部与 12 位 agentFlowId 内部误匹配。
#      为这两个假数字走了三轮取证。
#   ③ 真命中只有 2 处，是 scripts/probe-utc-http.sh 里我自己构造的 FAKE_ICCID
#      （设计前提「命中 0 行」已由 utc-http-after.txt 的 H01/H04/H09 = arr:0 证实）。
#   → 结论：**形状命中 ≠ 语义泄漏**。工具必须自己区分真阳/假阳，
#     与 audit-tmp-creds.sh 的 HARDCODED vs QUOTED/VAR_REF/REDACTED 分级是同一件事。
#
# 四条设计纪律（每条都对应一次真实踩坑）：
#   A. **长数字类模式一律带前后边界** `(^|[^0-9])…([^0-9]|$)`，否则在哈希串/长 ID 内部误匹配。
#   B. **分母必须独立统计**：TOTAL 不套白名单；SCANNED != TOTAL 就不得报 CLEAN
#      （audit-tmp-creds.sh 已因白名单漏 .runlog 报过 CLEAN_PARTIAL，同类盲区三次）。
#   C. **自指文件必须显式剔除并计数**：取证归档会原样保留命中值，
#      不剔除的话每扫一次数字就变一次，且没人知道为什么变。
#   D. **合成值单独分级为 SYNTHETIC**：变量名形如 FAKE_/DUMMY_/SAMPLE_/MOCK_/TEST_ 的赋值行
#      不算泄漏，但要报出来让人复核，不能静默放过。
#
# ★ 本工具自身的已知假阴性通道（2026-11-05 第 2 轮实测后必须声明）：
#   为了修掉「说明在行 9、值在行 10 → 被判 REAL」这个假阳性，SYNTHETIC 改成看
#   **命中行 + 前 3 行**的上下文窗口。代价是：**任何真实 iccid，只要它前 3 行内
#   出现「假卡号/构造值/FAKE_」等字样，就会被洗成 SYNTHETIC 而放过。**
#   → 所以 SYNTHETIC 计数**不是**可以只看总数的绿灯：每次它变化，都必须逐条打开
#     命中行人工确认「这真的是合成值」。本工具降低的是重复取证成本，
#     **不替代人工语义判定**。EVIDENCE_COPY 同理。
#   → 另：分级顺序为 REDACTED > SYNTHETIC > EVIDENCE_COPY，故一个既是引用副本、
#     上下文又含合成值关键词的命中会归 SYNTHETIC（本轮 09 号归档的 21/22 行即如此，
#     EVIDENCE_COPY 当前为 0，保留该级用于上下文不含关键词的引用副本）。
#
# 用法（本工具是 PowerShell 实现，须在 PowerShell 里跑）：
#   先 cd 到仓根，然后：
#     $c=[IO.File]::ReadAllText((Resolve-Path '.\scripts\audit-pii.ps1').Path); Invoke-Expression $c
#   （用 Invoke-Expression 时 $PSScriptRoot 为空，故 root 退化为当前目录 —— 必须先 cd 到仓根。）
#   ★ 环境坑：本机裸 `bash` 被 WSL 接管，会报 NAT 故障并返回 -1；但 Git for Windows 自带的
#     `C:\Program Files\Git\bin\bash.exe`（MINGW64 + GNU grep 3.0）**可用**，
#     audit-tmp-creds.sh / watch-cline.sh 等 .sh 闸门一律走它。
#     教训：说「某工具不可用」之前，先穷举它的常见安装位置（我曾因此白绕一圈）。
#   退出判据看最后一行：PII_CLEAN / PII_NO_REAL_HIT / PII_FOUND / PII_PARTIAL_SCAN
#   （只有 PII_CLEAN 与 PII_NO_REAL_HIT 可放行；PII_PARTIAL_SCAN 表示扫描面不完整，等同不通过）
#
# 安全边界：只读。只输出计数、文件名、行号与**掩码后**的片段；不输出任何完整命中值。

$ErrorActionPreference = 'Stop'
# $PSScriptRoot 只在「以脚本文件方式执行」时有值；用 Invoke-Expression 跑时为 $null，
# 此时退化为当前目录（调用方须先 cd 到仓根）。
$root = if ($PSScriptRoot) { (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path } else { (Get-Location).Path }
Set-Location -LiteralPath $root

$MO = [System.Text.RegularExpressions.RegexOptions]::Multiline
$SELF = 'scripts\audit-pii.ps1'          # 自指文件（含正则模式与 FAKE_ 字样）
$SKIP_DIRS = '\\\.git\\|\\target\\|\\node_modules\\'

# 判据表：名称 / 带边界正则 / 语义
$PATTERNS = @(
  @{ n = 'ICCID_20';  re = '(^|[^0-9])[0-9]{20}([^0-9]|$)';            d = '20 位纯数字（iccid 形态）' },
  @{ n = 'MSISDN_11'; re = '(^|[^0-9])1[3-9][0-9]{9}([^0-9]|$)';       d = '11 位 1[3-9]xxxxxxxxx（手机号形态）' },
  @{ n = 'OPENID';    re = '"openId"\s*:\s*"[^"]{6,}"';                 d = 'openId 键值对（假名化标识，掩数字无效）' }
)
# 无边界对照组：仅用于说明「不加边界会多出多少假命中」。
#   ★ loose 标记必须存在：首轮实测（2026-11-05）发现对照组也走了语义分级，
#     导致同一处命中被计两次（SYNTHETIC 报 2 而实际 1、EVIDENCE_COPY 报 4 而实际 2）。
$LOOSE = @(
  @{ n = 'LOOSE_20';  re = '[0-9]{20}';        loose = $true },
  @{ n = 'LOOSE_11';  re = '1[3-9][0-9]{9}';   loose = $true }
)
# 合成值判据：**命中行及其前 3 行**里出现这些关键词 → 归 SYNTHETIC 而非 PII_FOUND
$SYNTH = 'FAKE_|DUMMY_|SAMPLE_|MOCK_|TEST_|EXAMPLE_|PLACEHOLDER_|不存在的假卡号|假卡号|构造值'
# 已脱敏占位：命中值是这类占位符 → 归 REDACTED，不算泄漏
$REDACT = '<REDACTED|REDACTED-|#{6,}|\*{6,}'
# 证据副本：命中行形如「路径:行号: 值」→ 它是**对另一处命中的引用**（取证归档常见），
#   归 EVIDENCE_COPY 而非 REAL。没有这一级，09-pii-全仓判定.txt 里原样保留的 2 处构造值
#   会被判成 REAL，把 PII_SYNTHETIC_ONLY 顶成 PII_FOUND。
#   注意：这**不是**放过它——它仍被计数并打印，只是语义归类不同，须人工复核引用源是否已定性。
$EVID = ':[0-9]+:\s'

$all = @(Get-ChildItem -Recurse -File | Where-Object { $_.FullName -notmatch $SKIP_DIRS })
$TOTAL = $all.Count
$scanned = 0; $unscannable = @(); $selfSkipped = 0

"==== 0. 扫描范围（分母独立统计，不套白名单）===="
"  root=$root"
"  TOTAL=$TOTAL"

$res = @{}
foreach ($p in ($PATTERNS + $LOOSE)) { $res[$p.n] = @{ occ = 0; files = @(); hits = @() } }
$synthHits = @(); $redactHits = @(); $evidHits = @()

foreach ($f in $all) {
  $rel = $f.FullName.Substring($root.Length + 1)
  if ($rel -eq $SELF) { $selfSkipped++; continue }        # 纪律 C：剔除自指
  try {
    $txt = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  } catch { $unscannable += $rel; continue }
  $scanned++
  $lines = $txt -split "`n"
  foreach ($p in ($PATTERNS + $LOOSE)) {
    foreach ($m in [regex]::Matches($txt, $p.re, $MO)) {
      $ln = ($txt.Substring(0, $m.Index) -split "`n").Count
      $res[$p.n].occ++
      if ($res[$p.n].files -notcontains $rel) { $res[$p.n].files += $rel }
      if ($p.loose) { continue }                 # 对照组只计数量，不参与语义分级
      $val = $m.Value.Trim()
      $line = $lines[$ln - 1]
      # ★ SYNTHETIC 必须看**上下文窗口**（命中行 + 前 3 行）：首轮实测把
      #   probe-utc-http.sh:10 判成 REAL，因为「不存在的假卡号」这句说明在**行 9**、
      #   值在行 10 —— 只查命中行必然漏。合成值的语义说明几乎从不在值所在的那一行。
      $from = [Math]::Max(0, $ln - 4)
      $ctx = ($lines[$from..($ln - 1)] -join ' ')
      $cls = 'REAL'
      if ($val -match $REDACT) { $cls = 'REDACTED' }
      elseif ($ctx -match $SYNTH) { $cls = 'SYNTHETIC' }
      # EVIDENCE_COPY 只用命中行本身：引用格式「路径:行号: 值」必在同一行；
      #   若也用上下文，日志时间戳等 `:数字:` 形态会造成误判。
      elseif ($line -match $EVID) { $cls = 'EVIDENCE_COPY' }
      # 只报核心字符长度：数字类判据的 $val 含前后边界字符，直接用 $val.Length 会多算 1~2
      $core = if ($p.n -eq 'OPENID') { $val } else { ($val -replace '[^0-9]', '') }
      $masked = ($core -replace '[0-9A-Za-z]', '#')
      $rec = "  [$cls] $rel`:$ln  corelen=$($core.Length) shape=$masked"
      $res[$p.n].hits += $rec
      if ($cls -eq 'SYNTHETIC') { $synthHits += $rec }
      if ($cls -eq 'REDACTED') { $redactHits += $rec }
      if ($cls -eq 'EVIDENCE_COPY') { $evidHits += $rec }
    }
  }
}

"  SCANNED=$scanned  SELF_SKIPPED=$selfSkipped  UNSCANNABLE=$(@($unscannable).Count)"
if ($unscannable.Count -gt 0) { $unscannable | ForEach-Object { "    ! $_" } }

"`n==== 1. 带边界判据（真命中）===="
foreach ($p in $PATTERNS) {
  $r = $res[$p.n]
  "  $($p.n)  occ=$($r.occ)   # $($p.d)"
  $r.hits | Select-Object -First 12 | ForEach-Object { $_ }
}

"`n==== 2. 无边界对照（说明为何必须加边界，这些是假命中）===="
foreach ($p in $LOOSE) { "  $($p.n)  occ=$($res[$p.n].occ)" }

"`n==== 3. 分级汇总 ===="
"  SYNTHETIC=$(@($synthHits).Count)  EVIDENCE_COPY=$(@($evidHits).Count)  REDACTED=$(@($redactHits).Count)"
if ($evidHits.Count -gt 0) {
  "  ---- EVIDENCE_COPY 明细（引用副本，须人工复核其引用源是否已定性）----"
  $evidHits | Select-Object -First 12 | ForEach-Object { $_ }
}

# 真阳计数 = 带边界命中里既非 SYNTHETIC / EVIDENCE_COPY / REDACTED 的
$real = 0
foreach ($p in $PATTERNS) { $real += @($res[$p.n].hits | Where-Object { $_ -match '^\s*\[REAL\]' }).Count }
"  REAL=$real"

"`n==== 4. 结论 ===="
$partial = ($scanned + $selfSkipped + @($unscannable).Count) -ne $TOTAL
$nonReal = @($synthHits).Count + @($evidHits).Count
if ($partial) {
  "PII_PARTIAL_SCAN: SCANNED($scanned)+SELF($selfSkipped)+UNSCANNABLE($(@($unscannable).Count)) != TOTAL($TOTAL)"
  "  → 纪律 B：扫描面不完整时不得报 CLEAN。先查差在哪。"
} elseif ($real -gt 0) {
  "PII_FOUND: REAL=$real —— 存在未脱敏、未归类的个人数据形态命中。"
  "  → 若该仓已推送远端，须评估是否 rewrite history；先逐条人工语义分类再决定。"
} elseif ($nonReal -gt 0) {
  "PII_NO_REAL_HIT: REAL=0；SYNTHETIC=$(@($synthHits).Count) EVIDENCE_COPY=$(@($evidHits).Count) REDACTED=$(@($redactHits).Count)"
  "  → 无需 rewrite history。但 SYNTHETIC / EVIDENCE_COPY 的**归类是工具按行内关键词推断的**，"
  "    每次新增归档后须复核这两个计数是否变化，变了就逐条看新增的那条是不是真的合成值。"
} else {
  "PII_CLEAN: REAL=0 SYNTHETIC=0 EVIDENCE_COPY=0 REDACTED=$(@($redactHits).Count)，扫描面 $scanned/$TOTAL 完整。"
}
"AUDIT_PII_DONE"
