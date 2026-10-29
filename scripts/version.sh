#!/usr/bin/env bash
#
# 版本号管理。单一事实来源是 bin/socat-forward 顶部的 VERSION，
# 本脚本负责读取、校验、升级，以及给发布打标签。
#
# 用法：
#   scripts/version.sh get                 打印当前版本
#   scripts/version.sh check               校验脚本 / README 徽章 / CHANGELOG 是否一致
#   scripts/version.sh bump <x.y.z>        升级版本号（要求 CHANGELOG 条目已写好）
#   scripts/version.sh tag [--push]        为当前版本创建 vX.Y.Z 注释标签（可选推送）
#
# 发布流程：
#   1. 把 CHANGELOG 的 [Unreleased] 改成 ## [x.y.z] - YYYY-MM-DD
#   2. make bump-version VERSION=x.y.z
#   3. 提交后 make tag PUSH=1

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/bin/socat-forward"
README="$ROOT/README.md"
CHANGELOG="$ROOT/CHANGELOG.md"

info() { printf '[*] %s\n' "$*"; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
用法：
  scripts/version.sh get                 打印当前版本
  scripts/version.sh check               校验脚本 / README 徽章 / CHANGELOG 是否一致
  scripts/version.sh bump <x.y.z>        升级版本号（要求 CHANGELOG 条目已写好）
  scripts/version.sh tag [--push]        为当前版本创建 vX.Y.Z 注释标签（可选推送）

发布流程：
  1. 把 CHANGELOG 的 [Unreleased] 改成 ## [x.y.z] - YYYY-MM-DD
  2. make bump-version VERSION=x.y.z
  3. 提交后 make tag PUSH=1
EOF
}

script_version() {
  local v
  v=$(sed -n 's/^VERSION="\([^"]*\)".*/\1/p' "$SCRIPT" | head -n1)
  [[ -n $v ]] || die "无法从 $SCRIPT 读取 VERSION"
  printf '%s\n' "$v"
}

readme_version() {
  sed -n 's#.*badge/version-\([0-9][0-9.]*\)-informational.*#\1#p' "$README" | head -n1
}

changelog_version() {
  sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' "$CHANGELOG" | head -n1
}

cmd_check() {
  local sv rv cv failed=0
  sv=$(script_version)
  rv=$(readme_version)
  cv=$(changelog_version)

  [[ -n $rv ]] || die "README 中找不到版本徽章（version-x.y.z-informational）"
  [[ -n $cv ]] || die "CHANGELOG 中找不到版本标题（## [x.y.z]）"

  printf '    脚本 VERSION: %s\n' "$sv"
  printf '    README 徽章:  %s\n' "$rv"
  printf '    CHANGELOG:    %s\n' "$cv"

  if [[ $rv != "$sv" ]]; then
    printf '[x] README 徽章与脚本版本不一致（应为 %s）\n' "$sv" >&2
    failed=1
  fi
  if [[ $cv != "$sv" ]]; then
    printf '[x] CHANGELOG 最新条目与脚本版本不一致（应为 %s）\n' "$sv" >&2
    failed=1
  fi
  (( failed == 0 )) || exit 1
  info "版本号一致：$sv"
}

cmd_bump() {
  local new=${1:-} old ver_re
  [[ -n $new ]] || die "用法：$0 bump <x.y.z>"
  ver_re='^[0-9]+\.[0-9]+\.[0-9]+$'
  [[ $new =~ $ver_re ]] || die "版本号必须是 x.y.z 形式：$new"

  old=$(script_version)
  [[ $new != "$old" ]] || die "版本号未变化：$new"
  [[ $(changelog_version) == "$new" ]] ||
    die "请先在 $CHANGELOG 顶部写好 [$new] 的条目，再执行 bump"

  # 用 awk 以字面量替换，避免版本号里的 . 被当作正则
  awk -v new="$new" '
    /^VERSION="[^"]*"$/ && !done { print "VERSION=\"" new "\""; done=1; next }
    { print }
  ' "$SCRIPT" >"$SCRIPT.tmp"
  mv "$SCRIPT.tmp" "$SCRIPT"

  awk -v old="$old" -v new="$new" '
    {
      if (!done && index($0, "badge/version-" old "-informational")) {
        gsub("badge/version-" old "-informational", "badge/version-" new "-informational")
        done=1
      }
      print
    }
  ' "$README" >"$README.tmp"
  mv "$README.tmp" "$README"

  chmod 0755 "$SCRIPT"
  info "版本号：$old -> $new"
  cmd_check
}

cmd_tag() {
  local push=0 v headv
  [[ ${1:-} == "--push" ]] && push=1
  v=$(script_version)

  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "不是 git 仓库"
  headv=$(git -C "$ROOT" show "HEAD:bin/socat-forward" |
    sed -n 's/^VERSION="\([^"]*\)".*/\1/p' | head -n1)
  [[ $headv == "$v" ]] || die "版本 $v 尚未提交到 HEAD（HEAD 为 ${headv:-未知}），请先提交"

  if git -C "$ROOT" rev-parse -q --verify "refs/tags/v$v" >/dev/null; then
    info "标签 v$v 已存在"
  else
    git -C "$ROOT" tag -a "v$v" -m "socat-forward v$v"
    info "已创建标签 v$v"
  fi

  if (( push )); then
    git -C "$ROOT" push origin "v$v"
    info "已推送标签 v$v"
  else
    info "推送标签：git push origin v$v（或 make tag PUSH=1）"
  fi
}

case ${1:-} in
  get)   script_version ;;
  check) cmd_check ;;
  bump)  shift; cmd_bump "${1:-}" ;;
  tag)   shift; cmd_tag "${1:-}" ;;
  -h|--help|help|"") usage ;;
  *) die "未知子命令：$1（-h 查看用法）" ;;
esac
