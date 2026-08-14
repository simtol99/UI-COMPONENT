#!/usr/bin/env bash
#
# extract-my-prompts.sh
# ─────────────────────────────────────────────────────────────
# 현재 폴더에 해당하는 Claude Code 세션에서
# "내가 입력한 프롬프트"만 뽑아 Markdown 파일로 저장한다.
#
# 기본 동작은 "이번(최신) 세션 1개"만 추출한다.
#
# 사용법:
#   ./extract-my-prompts.sh                    # 이번 세션 → my-prompts.md
#   ./extract-my-prompts.sh <sessionId>        # 특정 세션 ID 지정
#   ./extract-my-prompts.sh --all              # 이 폴더의 모든 세션 합본
#   ./extract-my-prompts.sh -o out.md          # 출력 파일명 지정
#   ./extract-my-prompts.sh --cwd /경로        # 대상 프로젝트 폴더 지정(기본: 현재 폴더)
#   (옵션 조합 가능:  ./extract-my-prompts.sh --all -o all.md)
#
# 동작 원리:
#   Claude Code는 대화를 ~/.claude/projects/<폴더>/<세션>.jsonl 로 저장한다.
#   각 줄에 cwd·sessionId 필드가 있다.
#   기본 모드는 cwd가 일치하는 jsonl 중 가장 최근에 수정된 1개(= 이번 세션)만 본다.
#   user 메시지 중 "내가 친 텍스트"만 남기고 도구 출력·메타·시스템 주입은 제외한다.
#   파싱은 추가 설치 없는 python3 로 처리한다(jq 불필요).

set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PROJECTS_DIR="$CLAUDE_DIR/projects"

# ── 인자 파싱 ────────────────────────────────────────────────
MODE="session"          # session | all
SESSION_ID=""           # 명시한 세션 ID(.jsonl 제거한 UUID)
TARGET_CWD="$PWD"
OUT="my-prompts.md"

while [ $# -gt 0 ]; do
  case "$1" in
    --all)   MODE="all"; shift ;;
    -o)      OUT="${2:?-o 다음에 파일명이 필요합니다}"; shift 2 ;;
    --cwd)   TARGET_CWD="${2:?--cwd 다음에 경로가 필요합니다}"; shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    -*)
      echo "❌ 알 수 없는 옵션: $1"; exit 1 ;;
    *)
      # 위치 인자 = 세션 ID (.jsonl 확장자 붙여줘도 허용)
      SESSION_ID="${1%.jsonl}"; MODE="session"; shift ;;
  esac
done

# 사전 점검
command -v python3 >/dev/null 2>&1 || { echo "❌ python3 가 필요합니다."; exit 1; }
[ -d "$PROJECTS_DIR" ] || { echo "❌ 세션 폴더가 없습니다: $PROJECTS_DIR"; exit 1; }

# 절대경로로 정규화(상대경로로 줘도 cwd 매칭이 되도록)
TARGET_CWD="$(cd "$TARGET_CWD" 2>/dev/null && pwd || echo "$TARGET_CWD")"

python3 - "$PROJECTS_DIR" "$TARGET_CWD" "$OUT" "$MODE" "$SESSION_ID" << 'PYEOF'
import json, sys, glob, os, re
from datetime import datetime

projects, target_cwd, out, mode, session_id = sys.argv[1:6]

# 1) cwd 가 일치하는 세션 파일 수집
matched = []
for f in glob.glob(os.path.join(projects, "*", "*.jsonl")):
    try:
        with open(f, encoding="utf-8") as fh:
            for line in fh:
                try:
                    if json.loads(line).get("cwd") == target_cwd:
                        matched.append(f); break
                except Exception:
                    continue
    except Exception:
        continue

if not matched:
    print(f"⚠️  현재 폴더에 해당하는 세션을 찾지 못했습니다: {target_cwd}")
    print("    인자로 폴더를 지정해 보세요:  ./extract-my-prompts.sh --cwd /경로")
    sys.exit(1)

# 2) 대상 파일 선정
if mode == "all":
    files = sorted(matched)
elif session_id:
    files = [f for f in matched if os.path.splitext(os.path.basename(f))[0] == session_id]
    if not files:
        # cwd 밖일 수도 있으니 전체에서 한 번 더 탐색
        cand = glob.glob(os.path.join(projects, "*", session_id + ".jsonl"))
        files = cand
    if not files:
        print(f"⚠️  세션 ID 를 찾지 못했습니다: {session_id}")
        sys.exit(1)
else:
    # 기본: cwd 일치 파일 중 가장 최근 수정본 = 이번 세션
    files = [max(matched, key=os.path.getmtime)]

# 3) 내가 입력한 프롬프트만 추출
prompts = []
for f in files:
    with open(f, encoding="utf-8") as fh:
        for line in fh:
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get("type") != "user" or o.get("isMeta"):
                continue
            c = o.get("message", {}).get("content")
            if isinstance(c, str):
                text = c
            elif isinstance(c, list):  # 배열이면 text 블록만(도구 결과 제외)
                text = "\n".join(b.get("text", "") for b in c
                                 if isinstance(b, dict) and b.get("type") == "text")
            else:
                text = ""
            # IDE 확장이 주입하는 컨텍스트 블록(<ide_opened_file>…</ide_opened_file>,
            # <ide_selection>…</ide_selection> 등)은 내가 친 텍스트가 아니므로 도려낸다.
            # 블록만 제거하고 실제 입력은 보존한다(통째로 버리지 않음).
            text = re.sub(r"<ide_[^>]*>.*?</ide_[^>]*>", "", text, flags=re.DOTALL)
            text = text.strip()
            # 빈 줄 / 시스템 주입(local-command·system-reminder 등) / Caveat 래퍼 제외.
            # 단, 사용자가 친 <태그> 프롬프트는 살리기 위해 known 래퍼만 정확히 거른다.
            if not text or text.startswith("Caveat:"):
                continue
            low = text.lstrip()
            if low.startswith("<bash-input") or low.startswith("<bash-stdout") \
               or low.startswith("<local-command") or low.startswith("<command-") \
               or low.startswith("<system-reminder"):
                continue
            prompts.append((o.get("timestamp", ""), text))

# 4) 시간순 정렬 + 중복 제거(연속 동일 입력)
prompts.sort(key=lambda x: x[0])
seen, uniq = None, []
for ts, t in prompts:
    if t != seen:
        uniq.append((ts, t)); seen = t

# 5) Markdown 작성
scope = "이번 세션" if (mode == "session" and not session_id) else \
        (f"세션 {session_id}" if session_id else "cwd 전체 합본")
with open(out, "w", encoding="utf-8") as w:
    w.write("# Claude Code 프롬프트 모음\n\n")
    w.write(f"- 프로젝트: `{target_cwd}`\n")
    w.write(f"- 범위: {scope}\n")
    w.write(f"- 추출 시각: {datetime.now():%Y-%m-%d %H:%M:%S}\n")
    w.write(f"- 세션 수: {len(files)} / 프롬프트 수: {len(uniq)}\n\n---\n\n")
    for i, (ts, t) in enumerate(uniq, 1):
        day = ts[:10] if ts else ""
        w.write(f"### {i}. {day}\n\n{t}\n\n")

print(f"✅ 완료: {out}  ({scope}, 세션 {len(files)}개, 프롬프트 {len(uniq)}개)")
PYEOF
