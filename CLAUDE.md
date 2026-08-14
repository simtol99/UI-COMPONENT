# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 저장소 개요

CareerFoundry의 "32 UI Elements" 목록을 기반으로 한 UI 컴포넌트 카탈로그 사이트. 빌드 시스템·패키지 매니저·번들러 없이 순수 정적 HTML/CSS/JS로 동작한다.

- **`index.html`** — 이 저장소의 메인 산출물. 좌측에 32가지 UI 요소 + "레이어·알림" 그룹(Alert Dialog, Confirm Dialog, Toast, Snackbar, Bottom Sheet, Popover) 목록을, 우측에 선택한 컴포넌트의 이름/정의/설명과 미리보기·HTML·CSS·JS 탭을 보여준다.
- **`docs/resource/`** — 위 카탈로그를 만들 때 참고한 원본 디자인 시안 8개. 각각 완전히 독립된(self-contained) 단일 HTML 파일이며 서로 코드를 공유하지 않는다.
- **`rules/anti-ai-slop.md`** — 이 저장소에서 이미지·HTML·SVG를 생성할 때 반드시 지켜야 하는 시각 스타일 규칙(아래 참고).
- **`extract-my-prompts.sh`** — `~/.claude/projects/`에 저장된 이 프로젝트의 Claude Code 세션 로그에서 사용자가 입력한 프롬프트만 추출해 Markdown으로 저장하는 개발 유틸리티. 코드베이스 자체와는 무관.
- **`rules/settings.local.json`** — `Stop` 훅으로 `extract-my-prompts.sh`를 등록해, Claude Code 세션이 끝날 때마다 자동으로 프롬프트 기록을 갱신한다. 즉 이 저장소에서의 모든 세션은 종료 시 `Prompt.md`(스크립트 기본 출력 파일명)가 자동으로 다시 쓰인다는 뜻이므로, 그 파일의 변경 이력은 별도로 신경 쓸 필요 없다.

## 실행 / 확인 방법

별도 빌드·설치 과정이 없다. 브라우저에서 HTML 파일을 직접 열거나, 정적 서버로 서빙해서 확인한다.

```bash
open index.html                                          # 메인 카탈로그를 macOS에서 바로 열기
python3 -m http.server 8000                               # 또는 로컬 서버로 서빙 후 http://localhost:8000
./extract-my-prompts.sh                                   # 이번 세션에서 내가 입력한 프롬프트만 my-prompts.md로 추출
```

린트/테스트/빌드 명령은 존재하지 않는다. UI를 바꾼 뒤에는 브라우저(또는 Playwright 등)로 직접 열어 클릭 동작까지 확인해야 한다 — 타입체커나 빌드가 없어 문법 오류 외의 문제를 잡아주지 않는다.

## `index.html` 구조

- **데이터 배열**: `ELEMENTS`(1~16) + `ELEMENTS_2`(17~32) + `LAYER_ELEMENTS`(33~38, cat: `"layer"`)를 `DATA`로 합친다. 각 항목은 `{ n, name, ko, cat, desc, html, css, js }` 형태이며, `cat`은 `CATS`/`CAT_ORDER`에 정의된 카테고리 키(`layer`, `input`, `nav`, `info`, `container`) 중 하나다. 컴포넌트를 추가/수정할 때는 이 배열에서 해당 객체를 찾아 편집한다.
- **미리보기**: 각 항목의 `html`/`css`/`js`는 `buildSrcdoc()`으로 감싸져 `<iframe srcdoc>`에 주입된다. 즉 각 컴포넌트의 데모는 메인 페이지 스타일과 완전히 격리된 별도 문서에서 실행되므로, 데모에 필요한 CSS/JS는 반드시 해당 항목의 `css`/`js` 필드 안에 전부 포함해야 한다(메인 페이지의 `<style>`을 참조할 수 없다).
- **코드 표시/하이라이트**: `select()`가 탭 패널의 빈 `<code class="language-*">`에 원본 텍스트를 채운 뒤 `hljs.highlightElement()`(CDN의 highlight.js)로 하이라이트한다. 복사 버튼은 하이라이트되지 않은 원본 문자열을 클립보드에 복사한다.
- **주의 — `hidden` 속성과 `display` 충돌**: 오버레이형 컴포넌트(Modal, Alert Dialog, Confirm Dialog, Bottom Sheet 등)는 `<div class="xxx" hidden>` 식으로 열림/닫힘을 `hidden` 속성으로 제어하면서, CSS에서는 같은 클래스에 `display: flex`를 무조건 지정한다. 이 경우 클래스 선택자의 `display` 값이 브라우저 기본 `[hidden]{display:none}` 규칙을 특이도 순서상 덮어써서 항상 열린 상태로 보이는 버그가 생긴다. 이런 오버레이 컴포넌트를 새로 추가할 때는 반드시 `.xxx[hidden] { display: none; }` 규칙을 함께 추가해야 한다(기존 항목들에 이미 적용되어 있으니 그 패턴을 따를 것).

## 시각 스타일 규칙 (`rules/anti-ai-slop.md`)

이 저장소에서 HTML/이미지/SVG를 생성·수정할 때(특히 `index.html`) 반드시 지켜야 한다:

- **금지**: 모든 종류의 gradient(배경·텍스트 포함), 색 들어간 box-shadow·글로우·`backdrop-filter: blur`, hover/load 시의 transform·fade·pulse 등 장식용 애니메이션, 배경 워터마크/그리드/광선, 카드 상단 컬러 액센트 바, 이모지 불릿·과도한 뱃지, "Seamlessly/Elevate/Unlock" 류 마케팅 상투어.
- **강제**: 무채색 베이스 + 액센트 1색만 사용하고 색은 의미(상태·위계) 전달에만 쓴다. 그림자는 쓰더라도 `0 1px 2px rgba(0,0,0,.06)` 수준의 중성 회색 1단계로 제한. 구획은 효과가 아닌 `1px solid border`+여백으로 나눈다. `border-radius`는 0~8px. 위계는 색·효과가 아니라 크기·굵기·여백·정렬로 만든다.
- 모든 시각 요소는 "어떤 정보를 전달하는가"에 답할 수 있어야 하며, 답할 수 없으면 삭제한다.

## `docs/resource/` 참고 시안 컨벤션

- 디자인 토큰은 파일마다 `:root`의 CSS 커스텀 프로퍼티(`--bg`, `--text`, `--accent` 등)로 정의되며, 파일마다 팔레트와 변수명이 다르다.
- 외부 의존성은 CDN 링크로 로드된다 (Google Fonts, Tailwind CDN, lucide 아이콘 등 파일별로 상이). npm 패키지는 사용하지 않는다.
- 폰트: 한국어 본문은 주로 Noto Sans KR / Pretendard, 코드/모노스페이스는 JetBrains Mono를 사용하는 패턴이 반복된다.
- 모든 페이지의 `lang` 속성은 `ko`이며, UI 텍스트도 대부분 한국어로 작성되어 있다.
