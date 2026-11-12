#!/usr/bin/env bash
# 빌드 로그를 ci-logs-* 브랜치에 올린다 (로그 확인용).
# 사용법: push-log.sh <브랜치> <파일...>
set -u
branch="$1"; shift
tmp="$(mktemp -d)"
for f in "$@"; do [ -f "$f" ] && cp "$f" "$tmp/"; done
cd "$tmp" || exit 0
git init -q
git checkout -q -b "$branch"
echo "run ${GITHUB_RUN_ID:-} $(date -u +%FT%TZ)" > RUN.txt
git add -A
git -c user.name=ci -c user.email=ci@users.noreply.github.com commit -qm "logs ${GITHUB_RUN_ID:-}"
git push -q -f "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "HEAD:refs/heads/$branch" || true
