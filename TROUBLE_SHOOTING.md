# GitHub Pages 게시 · 트러블슈팅 가이드

정적 사이트(빌드 도구 없는 순수 HTML/CSS/JS 등)를 GitHub Pages로 게시할 때의 절차, 자동 배포 워크플로우, 실제로 겪을 수 있는 문제와 해결 방법을 정리한다. 다른 프로젝트에도 그대로 재사용 가능.

## 1. 게시 절차 (요약)

GitHub Pages를 켜는 방법은 두 가지다. 상황에 따라 고른다.

### 방법 A — Settings에서 브랜치 지정 (가장 단순, 수동 재배포 필요 없음)

1. `https://github.com/<owner>/<repo>/settings/pages` 접속
2. **Build and deployment → Source**: `Deploy from a branch`
3. **Branch**: 배포할 브랜치(보통 `main`) + `/ (root)` (또는 `/docs`) 선택 → **Save**
4. 1~2분 후 `https://<owner>.github.io/<repo>/`에서 확인

이후 해당 브랜치에 push하면 GitHub가 알아서 재배포한다. 별도 워크플로우 파일이 필요 없다.

### 방법 B — GitHub Actions로 배포 (세밀한 제어·빌드 단계가 필요할 때)

1. 저장소에 `.github/workflows/deploy-pages.yml` 추가 (아래 "배포 워크플로우" 참고)
2. `https://github.com/<owner>/<repo>/settings/pages` → **Source**를 `GitHub Actions`로 설정
   - 이미 워크플로우가 한 번 성공적으로 돌면 GitHub가 자동으로 이 값을 맞춰주는 경우도 있다.
3. 해당 워크플로우가 트리거되는 브랜치(보통 `main`)에 push하면 Actions 탭에서 배포가 진행된다.

**언제 B를 쓰나**: 정적 파일을 그대로 서빙하는 경우엔 A로 충분하다. 다만 A의 Branch/폴더 드롭다운이 UI 버그로 먹통이 되는 경우가 실제로 있었기 때문(§3-1 참고), 재현 가능하고 자동화된 B가 더 안정적이다. 빌드 스텝(번들러, 정적 사이트 생성기 등)이 필요하면 B가 사실상 필수다.

## 2. 배포 워크플로우 (GitHub Actions, 빌드 없는 정적 사이트 기준)

`.github/workflows/deploy-pages.yml`:

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Configure Pages
        uses: actions/configure-pages@v5
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: .
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

- `path: .`는 저장소 루트 전체를 그대로 게시한다는 뜻. 특정 폴더(`dist/`, `build/` 등)만 게시하려면 그 경로로 바꾼다.
- 빌드 단계가 필요하면(`npm run build` 등) `upload-pages-artifact` 앞에 빌드 스텝을 추가하고 `path`를 빌드 결과 폴더로 지정한다.
- `workflow_dispatch`는 Actions 탭에서 수동으로 재실행할 수 있게 해준다 — 배포 관련 디버깅 시 유용.
- `concurrency` 블록은 연속 push 시 이전 배포와 겹치지 않도록 취소·직렬화한다.

## 3. 문제 발생 시 해결 방법

### 3-1. Settings → Pages의 Save 버튼이 비활성화되어 눌리지 않음

**증상**: Source를 `Deploy from a branch`로, Branch/폴더도 올바르게 선택했는데 Save가 계속 회색으로 비활성.

**원인**: 화면에 표시된 값이 실제 "선택 변경" 이벤트로 인식되지 않는 GitHub Pages 설정 UI의 흔한 버그. 페이지가 로드되며 기본값을 미리 채워 보여주지만 내부적으로는 "변경 없음" 상태로 남아 있는 경우가 있다.

**해결**:
1. Branch 드롭다운을 `None`으로 바꿨다가 다시 원하는 브랜치로 재선택 → 폴더 드롭다운도 같은 방식으로 재선택 (change 이벤트를 강제로 발생시킴)
2. 그래도 안 되면 페이지 새로고침 후 재시도
3. 광고 차단기 등 브라우저 확장 프로그램이 스크립트를 막고 있을 수 있음 — 시크릿 창에서 재시도
4. 그래도 안 풀리면 §1 방법 B(GitHub Actions 배포)로 우회한다. 이쪽은 Source를 `GitHub Actions`로 바꾸는 것만으로 끝나고 브랜치/폴더 드롭다운 자체가 없어 같은 문제가 재현되지 않는다.

### 3-2. `GET /repos/<owner>/<repo>/pages` API가 404를 반환하는데 사이트는 이미 열림

**증상**: `curl https://api.github.com/repos/<owner>/<repo>/pages`가 `404 Not Found`를 반환하지만, 실제 사이트 URL(`https://<owner>.github.io/<repo>/`)은 정상 응답(200).

**원인**: 이 API 엔드포인트는 인증 없이 호출하면 정보를 숨기거나 지연 반영되는 경우가 있다. **API 응답을 신뢰하지 말고 실제 사이트 URL을 직접 확인**하는 게 더 정확하다.

**해결**:
```bash
curl -sI https://<owner>.github.io/<repo>/ | head -5
```
`HTTP/2 200`이 나오면 이미 게시되어 있는 것. Actions 탭(`https://github.com/<owner>/<repo>/actions`)에서 `pages build and deployment` 워크플로우의 성공 여부로도 교차 확인할 수 있다.

### 3-3. `gh` CLI가 없어서 Pages를 API로 켤 수 없음

**증상**: 로컬/에이전트 환경에 `gh` CLI가 설치되어 있지 않고, GitHub 토큰도 없어 `gh api repos/.../pages` 같은 명령을 쓸 수 없음.

**해결**: 토큰을 채팅/커맨드에 직접 노출시키는 방식은 피한다. 대신
1. 사람이 직접 Settings → Pages에서 한 번 켜거나(§1-A),
2. 워크플로우 파일(§1-B)을 추가해 push만으로 배포되게 만든다. 워크플로우 자체는 저장소에 이미 부여된 `GITHUB_TOKEN`(Actions 실행 시 자동 발급)으로 동작하므로 별도 토큰이 필요 없다.

### 3-4. 배포하려는 브랜치와 실제 게시하려는 내용이 다른 브랜치에 있음

**증상**: 최신 작업은 `feature/*` 브랜치에만 있고, Pages가 보는 `main`은 몇 커밋 뒤처져 있어 배포해도 옛날 내용이 보임.

**해결**:
```bash
git fetch origin
git checkout main
git merge feature/xxx --ff-only   # 히스토리가 갈라지지 않았다면 fast-forward로 충분
git push origin main
```
`--ff-only`가 실패하면(즉 main에서 별도 커밋이 있었다면) 일반 머지나 리베이스로 히스토리를 정리한 뒤 push한다. **main에 직접 push하는 행위이므로, 다른 사람과 공유하는 저장소라면 사전에 합의하고 진행한다.**

### 3-5. 배포는 성공했는데 새 내용이 안 보임 (캐시)

**해결**: 브라우저 강력 새로고침(Shift+Reload) 또는 시크릿 창으로 확인. GitHub Pages/CDN 캐시가 반영되기까지 1~2분 걸릴 수 있다. Actions 탭에서 최신 워크플로우 run이 실제로 `success`인지 먼저 확인한다.

## 4. 배포 후 확인 체크리스트

- [ ] Actions 탭의 최신 `Deploy to GitHub Pages`(또는 `pages build and deployment`) run이 `success`
- [ ] `curl -sI https://<owner>.github.io/<repo>/` → `HTTP/2 200`
- [ ] 주요 하위 페이지도 개별 확인 (예: `curl -sI https://<owner>.github.io/<repo>/some-page.html`)
- [ ] 브라우저에서 실제로 열어 콘솔 에러 없는지 확인
