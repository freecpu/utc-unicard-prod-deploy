#!/bin/bash
# ============================================================================
# audit-tmp-creds.sh — 审计 /tmp 下遗留脚本是否含**明文凭据值**
#
# 为什么需要它：
#   grep 命中 "password=" 不等于含明文凭据——可能是空占位（password=）、
#   变量引用（password=$PWD）、或命令行开关（--password）。
#   必须区分「有值」和「没值」，且**只报值的长度、绝不报值本身**。
#
# 输出分级：
#   HARDCODED  值长度 >= 4 且不含 $ 与反引号 → 疑似硬编码明文，须清理
#   VAR_REF    值里含 $ 或反引号            → 变量引用，非明文
#   QUOTED     值以引号开头且长度 <= 2      → 形如 grep '^X_PASSWORD=' 的**空模式串**，非明文
#   EMPTY      值长度 0                     → 空占位，非明文
#   SELF       命中在本脚本自身             → 自指误报，剔除
#
# ★ 2026-11-05 实测教训（第一版工具报了 60 处 HARDCODED，全是误报）：
#   被扫脚本里的写法是  PW=$(docker exec "$C" env | grep '^MYSQL_ROOT_PASSWORD=' | cut -d= -f2)
#   —— 从容器 env 动态取密码，`=` 后紧跟单引号收尾，**凭据根本没落盘**。
#   第一版只按「值非空」判 HARDCODED，把这种好写法当成泄漏，会引发不必要的
#   凭据轮换与处置动作。故新增 QUOTED 分级与 SELF 剔除。
#   教训：告警工具必须能区分真阳/假阳，且**必须自带能检出真阳性的自检**，
#         否则「全阴」可能只是工具瞎了（见 selftest 模式）。
#
# 安全边界：只读（selftest 模式会在 /tmp 建一个含假明文的样本并即时删除）。
#           不打印任何凭据值，只打印键名与值长度。
# 用法： bash audit-tmp-creds.sh [目录，默认 /tmp]
#        bash audit-tmp-creds.sh selftest    # 自检：验证工具确实能检出真明文
#        AUDIT_DEPTH=99 bash audit-tmp-creds.sh <仓库根>   # 递归扫，提交前必跑
#
# ★ 提交前必跑：git 一旦提交，凭据就永久留在历史里，事后清理要 rewrite history。
#   故本仓库 git add 之前必须用 AUDIT_DEPTH=99 扫一遍全树（含归档的 .txt 证据）。
# ============================================================================
set -uo pipefail

SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"

# ---- selftest：正控 + 负控成对。缺一不可 ----
# 为什么必须有它：若工具因正则写错而永远报 0，"CLEAN" 就是假阴性，
# 比误报更危险——它会让人以为凭据面已经干净。
# ★ 2026-11-05 实测：第一版 selftest 就抓出了真缺陷。样本写的是 PW=fakePlainValue123，
#   而当时正则只含 password 全称，短别名 PW=/PWD= 不在范围内 → HARDCODED=0 →
#   SELFTEST_FAIL。也就是说此前那句 "CLEAN: 未发现明文凭据" 是**假的**。
#   故正则已扩到 pw/pwd 短别名，且 selftest 必须同时验两个方向：
#     正控 —— 真明文（全称与短别名各一）必须被报成 HARDCODED
#     负控 —— grep '^X_PASSWORD=' 这种引号收尾的写法必须被归到 QUOTED，不得误报
if [ "${1:-}" = "selftest" ]; then
  D="$(mktemp -d /tmp/audit-selftest.XXXXXX)"
  trap 'rm -rf "$D"' EXIT
  # 正控 2 条（PASSWORD 全称 + PW 短别名）、变量引用 1 条、引号空串 1 条
  printf '%s\n' 'PASSWORD=fakePlainValue123' 'PW=anotherFakeValue' "TOKEN=''" 'SECRET=$DYN' > "$D/pos.sh"
  # 负控 A：从容器 env 动态取密码的写法，凭据不落盘，必须判 QUOTED
  printf '%s\n' "grep '^MYSQL_ROOT_PASSWORD=' x" > "$D/neg.sh"
  # 负控 B：脱敏脚本自己的 sed 源文本 → 必须判 REGEX_FRAG + REDACTED，不得报泄漏
  printf '%s\n' "sed -e 's/TOKEN=[^ ]*/TOKEN=REDACTED/g'" > "$D/mask.sh"
  # 负控 C：归档证据里已掩好的输出 → 必须判 REDACTED
  printf '%s\n' 'unit_environment=Environment=OPENAPI_TOKEN=REDACTED' > "$D/evidence.txt"
  OUT="$(bash "$SELF" "$D" 2>&1)"
  get() { printf '%s' "$OUT" | grep -oE "$1=[0-9]+" | head -1 | cut -d= -f2; }
  P="$(get HARDCODED)"; Q="$(get QUOTED)"; V="$(get VAR_REF)"; R="$(get REDACTED)"; G="$(get REGEX_FRAG)"
  echo "selftest 实测/期望："
  echo "  HARDCODED = ${P:-?} / 2   （正控：真明文必须被检出，全称与短别名各一）"
  echo "  QUOTED    = ${Q:-?} / 2   （负控A：动态取值不得误报）"
  echo "  VAR_REF   = ${V:-?} / 1   （变量引用）"
  echo "  REDACTED  = ${R:-?} / 2   （负控C+B：已掩好的占位符不得误报）"
  echo "  REGEX_FRAG= ${G:-?} / 1   （负控B：sed 源文本不得误报）"
  RC=0
  [ "${P:-0}" = "2" ] || { echo "  ✗ 正控失败：真明文未被检出（全称或短别名漏配）→ 任何 CLEAN 结论都不可信"; RC=1; }
  [ "${Q:-0}" = "2" ] || { echo "  ✗ 负控A失败：引号收尾的动态取值被误判 → 会产生虚假安全警报"; RC=1; }
  [ "${V:-0}" = "1" ] || { echo "  ✗ 变量引用未被识别"; RC=1; }
  [ "${R:-0}" = "2" ] || { echo "  ✗ 负控C失败：REDACTED 占位符被误判为明文"; RC=1; }
  [ "${G:-0}" = "1" ] || { echo "  ✗ 负控B失败：sed 正则碎片被误判为明文"; RC=1; }
  [ "$RC" = "0" ] && echo "SELFTEST_OK: 1 组正控 + 3 组负控全部通过，CLEAN / ACTION_REQUIRED 结论均可信"
  if [ "$RC" != "0" ]; then
    echo "SELFTEST_FAIL: 工具不可信，禁止据其结论做任何处置"
    # 全 0 通常意味着内层 awk 直接语法错误（bash -n 查不出来），把原始输出摊开才好定位
    echo "---- 内层原始输出（用于定位）----"
    printf '%s\n' "$OUT" | tail -20
  fi
  exit $RC
fi

DIR="${1:-/tmp}"
# 键名覆盖全称与短别名（pw/pwd）。
# ★ 前置边界只能是 (^|[^A-Za-z0-9])，**不能把 _ 排除在外**：
#   实测第一版写成 [^A-Za-z0-9_] 后，MYSQL_ROOT_PASSWORD= 因为前面是下划线而
#   完全匹配不上——恰好把最该检出的真实写法变成假阴性。
#   排除字母数字即可挡住 xxxpassword 这类子串误配。
# grep -i 使 PW/Password/MYSQL_ROOT_PASSWORD 都能命中。
PAT='(^|[^A-Za-z0-9])(password|passwd|pwd|pw|secret|token|appkey|appid|accesskey)[[:space:]]*[:=][[:space:]]*[^[:space:]]*'

TOTAL=0; HARD=0; VAR=0; EMPTY=0; QUOTED=0; REDACTED=0; REGEXFRAG=0; SELFN=0; FILEN=0
HARD_FILES=""

# 用 find 而非 shell glob：
#   ① glob 只扫单层，扫仓库（含 变更留痕/ 子目录）会漏
#   ② 覆盖面要含 yml/properties/env/txt/md —— 归档的证据文件同样可能夹带凭据
#   ③ -print + while read 才能正确处理带空格/中文的路径
#   ④ ★ 必须含**无扩展名文件**（.gitignore / .gitattributes / Dockerfile / Makefile）。
#      2026-11-05 实测：本仓 staged 66 个文件，而旧白名单只扫到 64 个 ——
#      差的正是 .gitignore 与 .gitattributes。这类文件恰恰最容易被人顺手粘进 token，
#      而漏扫之后汇总照样打印 CLEAN，构成「在残缺扫描面上给出干净结论」的假阴性，
#      比报错更危险。
# AUDIT_DEPTH=1 时行为等同旧版（只扫目录本层）；扫仓库用 AUDIT_DEPTH=99。
FILES="$(find "$DIR" -maxdepth "${AUDIT_DEPTH:-1}" -type f -not -path '*/.git/*' \
           \( -name '*.sh' -o -name '*.json' -o -name '*.yml' -o -name '*.yaml' \
              -o -name '*.properties' -o -name '*.conf' -o -name '*.env' \
              -o -name '*.txt' -o -name '*.md' \
              -o -name '*.cfg' -o -name '*.ini' -o -name '*.xml' -o -name '*.http' \
              -o -name '.*ignore' -o -name '.*attributes' \
              -o -name 'Dockerfile*' -o -name 'Makefile*' -o -name '*.service' \) 2>/dev/null)"
[ -n "$FILES" ] || { echo "---- 汇总 ----"; echo "命中总数=0（${DIR} 下无待扫文件）"; echo "CLEAN: 无文件可扫（注意：这不代表安全，代表扫描面为空）"; exit 0; }

# ★ 扫描面覆盖率：让「CLEAN」这个结论自带它覆盖了多大范围。
#   没有这一行，读者无法区分「扫全了没命中」与「压根没扫到」。
#   分母排除 .git/（对象库不是源码面）与二进制（jar/图片/压缩包，本就不该文本扫）。
TOTAL_FILES="$(find "$DIR" -maxdepth "${AUDIT_DEPTH:-1}" -type f -not -path '*/.git/*' \
                 -not -name '*.jar' -not -name '*.png' -not -name '*.jpg' \
                 -not -name '*.zip' -not -name '*.gz' 2>/dev/null | wc -l | tr -d ' ')"
SCANNED_FILES="$(printf '%s\n' "$FILES" | grep -c . 2>/dev/null || echo 0)"

while IFS= read -r f; do
  [ -f "$f" ] || continue
  FILEN=$((FILEN+1))
  # 剔除自身：本脚本的注释里就写着 password= 这类字样，扫自己必然自指误报
  if [ "$(readlink -f "$f" 2>/dev/null)" = "$SELF" ]; then
    SELFN=$((SELFN+1)); continue
  fi
  # 逐条命中，只取键名与值长度
  while IFS=$'\t' read -r key vlen hasvar; do
    [ -n "$key" ] || continue
    TOTAL=$((TOTAL+1))
    if [ "$vlen" = "0" ]; then
      EMPTY=$((EMPTY+1))
    else
      case "$hasvar" in
        1) VAR=$((VAR+1)) ;;
        2) QUOTED=$((QUOTED+1)) ;;
        3) REDACTED=$((REDACTED+1)) ;;
        4) REGEXFRAG=$((REGEXFRAG+1)) ;;
        *) HARD=$((HARD+1))
           case "$HARD_FILES" in *"$f"*) ;; *) HARD_FILES="$HARD_FILES $f" ;; esac
           printf 'HARDCODED\t%s\tkey=%s\tvalue_len=%s\n' "$f" "$key" "$vlen" ;;
      esac
    fi
  done < <(grep -ohEi "$PAT" "$f" 2>/dev/null | awk -v SQ="$(printf '\047')" '
      BEGIN { # 动态构造「尾随引号/shell 标点」正则：awk 程序本身被单引号包裹，
              # 里面不能出现裸单引号，只能由 -v 注入。
              # ★ 必须含 右括号/右方括号/分号/竖线/与号/逗号/大于号：
              #   实测 sed 脱敏表达式行尾形如  secret=REDACTED/g 后跟 右括号+引号，
              #   匹配到的值长达 13 字符，只剥引号剥不到 REDACTED，会被误报成明文泄漏。
              QRE = "[" SQ "\")\\];|&,>]+$" }
              # ↑ 拼出的正则是  [ 单引号 " ) \ ] ; | & , > ] + $
              #   注意 "\"")  这种写法会让第二个引号提前闭合 awk 字符串、
              #   使后半段被当成 awk 代码 → 语法错误 → 内层扫描零输出、
              #   所有计数变 0。实测踩过：表现是 selftest 全 0 而无任何报错，
              #   故 selftest 失败时必须把内层原始输出打出来（见下面 FAIL 分支）。
      { # 取第一个 : 或 = 之后的部分作为值（值本身可能含 = ，如 base64 padding，
        # 所以不能用 -F 分割后取 $2）
        p=index($0,"="); q=index($0,":");
        if (p==0) p=99999; if (q==0) q=99999;
        s=(p<q)?p:q;
        k=substr($0,1,s-1); v=substr($0,s+1);
        # grep -o 会把前置边界字符一并带进匹配（如 _PASSWORD=），剥掉它，
        # 否则键名显示成 _password，与全称对不上，不便核对
        gsub(/^[^A-Za-z0-9]+/,"",k);
        gsub(/^[ \t]+|[ \t]+$/,"",k); gsub(/^[ \t]+|[ \t]+$/,"",v);
        # 分级（数字即 bash 侧的分支号）：
        #   5 EMPTY      值长度 0
        #   2 QUOTED     引号包裹的空串，形如  grep 后跟一个以等号结尾的引号模式串
        #                （从容器 env 动态取密码的写法，凭据根本不落盘）
        #   1 VAR_REF    值含 $ 或反引号 —— 变量引用
        #   3 REDACTED   值就是脱敏占位符（REDACTED / <MASKED> / *** / XXX）
        #                —— 2026-11-05 实测：归档证据里的 Environment=OPENAPI_TOKEN=REDACTED
        #                   与脱敏脚本自己的替换串 TOKEN=REDACTED 都被第一版报成明文泄漏
        #   4 REGEX_FRAG 值以正则/shell 元字符开头，或整体不含字母数字
        #                —— 脱敏脚本里的 sed 源文本（如 password:).*#\1 、TOKEN=[^ ）
        #   0 HARDCODED  以上都不是 → 疑似真明文
        #
        # ★ 已知盲区（必须诚实记录，不能假装工具是全知的）：
        #   真凭据若正好以 . ( ) / \ { } [ ] * ^ # & < > | ~ ; , + = ! ? 开头，
        #   会被误归到 REGEX_FRAG 而漏报。故本工具的输出**不能替代人工复核**：
        #   pre-commit 门禁报 ACTION_REQUIRED 时须逐行看命中行，报 CLEAN 时也建议
        #   对新增文件抽读一遍。工具的净自检（selftest）只保证它能检出常见形状。
        c=substr(v,1,1);
        vu=toupper(v);
        gsub(QRE,"",vu); gsub(/\/[GI]*$/,"",vu);   # 剥掉 sed 替换串尾巴 /g 与引号
        if (length(v)==0) h=5;
        else if ((c==SQ || c=="\"") && length(v)<=2) h=2;
        else if (v ~ /[$]/ || v ~ /`/) h=1;
        else if (vu=="REDACTED" || vu=="MASKED" || vu=="<MASKED>" || vu ~ /^\*+$/ || vu ~ /^X+$/) h=3;
        else if (v !~ /[A-Za-z0-9]/) h=4;
        else if (c ~ /[.()\/\\\{\}\[\]*^#&<>|~;,+=!?]/) h=4;
        else h=0;
        printf "%s\t%d\t%d\n", tolower(k), length(v), h }')
done <<< "$FILES"

echo "---- 汇总 ----"
echo "扫描文件数=${FILEN}  命中总数=${TOTAL}"
echo "  HARDCODED=${HARD}（须处置）  VAR_REF=${VAR}  QUOTED=${QUOTED}  REDACTED=${REDACTED}  REGEX_FRAG=${REGEXFRAG}  EMPTY=${EMPTY}"
echo "  剔除自指文件=${SELFN}"
# ★ 扫描面：白名单命中数 / 目录内文本文件总数。两者不等说明有文件没被扫到，
#   此时下面的 CLEAN 只能算「在已扫面上干净」，不能当全仓结论。
UNCOVERED=$(( TOTAL_FILES - SCANNED_FILES ))
[ "$UNCOVERED" -lt 0 ] && UNCOVERED=0
echo "  扫描面=${SCANNED_FILES}/${TOTAL_FILES}（未覆盖 ${UNCOVERED} 个，已排除 .git/ 与二进制）"
echo "含硬编码明文的文件清单："
for g in $HARD_FILES; do echo "  $g"; done
[ "$HARD" = "0" ] && echo "  (无)"
echo "---- 结论 ----"
if [ "$HARD" -gt 0 ]; then
  echo "ACTION_REQUIRED: ${HARD} 处疑似明文凭据，分布在 $(echo $HARD_FILES | wc -w) 个文件"
  echo "  下一步：逐行人工复核上面列出的文件（本工具有已知盲区，见文件头注释），"
  echo "          确认是真凭据则清理并轮换；确认是误报则补分级规则，不要直接改判据。"
elif [ "$UNCOVERED" -gt 0 ]; then
  # ★ 不报 CLEAN。扫描面不完整时报干净，是比报错更危险的假阴性。
  echo "CLEAN_PARTIAL: 已扫的 ${SCANNED_FILES} 个文件未发现硬编码明文凭据，"
  echo "  但目录下还有 ${UNCOVERED} 个文本文件不在白名单内、**没有被扫到**。"
  echo "  下一步：把这些文件补进上面的 find 白名单后重跑，或人工抽读。"
  echo "  在白名单补齐之前，不得把本结论当作全仓 CLEAN 使用。"
else
  echo "CLEAN: 未发现硬编码明文凭据（扫描面完整：${SCANNED_FILES}/${TOTAL_FILES}）"
  echo "  命中项归类：VAR_REF=${VAR} QUOTED=${QUOTED} REDACTED=${REDACTED} REGEX_FRAG=${REGEXFRAG} EMPTY=${EMPTY}"
  echo "  ⚠ 本 CLEAN 结论的前提是 selftest 通过（正控能检出真明文）。"
  echo "    且工具对「以正则元字符开头的真凭据」有盲区，新增文件仍建议人工抽读。"
fi
