#!/bin/bash
# ============================================================================
#  publish.sh — 把本仓库一键发布到你的 GitHub
#
#  用法：
#     ./publish.sh <你的GitHub用户名> <仓库名>
#  例如：
#     ./publish.sh zhangsan cleanshotx-cn-patch
#
#  脚本会自动完成：检查登录 → 创建远端仓库 → 推送代码。
#  全程不需要你把密码或 token 交给任何人，登录在浏览器里完成。
# ============================================================================
set -euo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; CYN=$'\033[36m'; DIM=$'\033[2m'; RST=$'\033[0m'
info() { echo "${CYN}▶${RST} $*"; }
ok()   { echo "${GRN}✓${RST} $*"; }
warn() { echo "${YEL}!${RST} $*"; }
die()  { echo "${RED}✗${RST} $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# ── 0. 参数 ─────────────────────────────────────────────────────────────────
GH_USER="${1:-}"
REPO_NAME="${2:-}"

if [[ -z "$GH_USER" || -z "$REPO_NAME" ]]; then
  cat <<EOF
用法: ./publish.sh <GitHub用户名> <仓库名>

例如:
  ./publish.sh zhangsan cleanshotx-cn-patch

仓库名建议用 cleanshotx-cn-patch（沿用上游命名，别人容易搜到）。
EOF
  exit 1
fi

# ── 1. 环境检查 ─────────────────────────────────────────────────────────────
command -v git >/dev/null 2>&1 || die "没找到 git，请先安装 Xcode 命令行工具：xcode-select --install"

# gh 可能在 ~/.local/bin（本机就是这样装的），补进 PATH
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"

# ── 2. 确保是 git 仓库 ──────────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  info "初始化 git 仓库…"
  git init -q -b main
  git config user.name  "$(git config --global user.name  || echo "$GH_USER")"
  git config user.email "$(git config --global user.email || echo "$GH_USER@users.noreply.github.com")"
  git add -A
  git commit -q -m "CleanShot X 5.0 简体中文补丁"
  ok "已创建初始提交"
fi

# 有未提交改动就先提交，避免推上去是旧内容
if [[ -n "$(git status --porcelain)" ]]; then
  info "发现未提交的改动，正在提交…"
  git add -A
  git commit -q -m "更新词条与脚本"
  ok "已提交"
fi

# ── 3. 登录 GitHub ──────────────────────────────────────────────────────────
if command -v gh >/dev/null 2>&1; then
  USE_GH=1
else
  USE_GH=0
  warn "未检测到 gh（GitHub CLI），将改用纯 git 推送。"
fi

if [[ "$USE_GH" == "1" ]]; then
  if ! gh auth status >/dev/null 2>&1; then
    info "需要先登录 GitHub（会打开浏览器，按提示输入一次性代码）…"
    echo
    gh auth login --hostname github.com --git-protocol https --web
    echo
  fi
  gh auth status >/dev/null 2>&1 || die "GitHub 登录未完成，请重新运行本脚本。"
  ok "GitHub 已登录"

  # ── 4. 创建远端仓库并推送 ────────────────────────────────────────────────
  if git remote get-url origin >/dev/null 2>&1; then
    info "已存在 origin，直接推送…"
    git push -u origin main
  else
    info "创建远端仓库 $GH_USER/$REPO_NAME 并推送…"
    gh repo create "$GH_USER/$REPO_NAME" \
      --public \
      --source=. \
      --remote=origin \
      --push \
      --description "CleanShot X 5.0 简体中文补丁 — 1011 条词条，运行时注入，无需修改原应用"
  fi
else
  # ── 无 gh：纯 git 路线 ──────────────────────────────────────────────────
  cat <<EOF

${YEL}没有 gh，需要你在 GitHub 网页上先建好空仓库：${RST}

  1. 打开 ${CYN}https://github.com/new${RST}
  2. Repository name 填：${CYN}$REPO_NAME${RST}
  3. 选 Public，${YEL}不要${RST}勾选 "Add a README file"
  4. 点 Create repository

建好后回到这里按回车，脚本会继续推送。
EOF
  read -r -p "按回车继续…" _

  REMOTE_URL="https://github.com/$GH_USER/$REPO_NAME.git"
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$REMOTE_URL"
  else
    git remote add origin "$REMOTE_URL"
  fi

  info "推送中（首次会提示输入用户名与密码，密码处请粘贴 Personal Access Token）…"
  echo "${DIM}  没有 token？到 https://github.com/settings/tokens 生成一个，勾选 repo 权限。${RST}"
  git push -u origin main
fi

# ── 5. 完成 ─────────────────────────────────────────────────────────────────
echo
ok "发布完成！"
echo
echo "  仓库地址：${CYN}https://github.com/$GH_USER/$REPO_NAME${RST}"
echo "  克隆命令：${DIM}git clone https://github.com/$GH_USER/$REPO_NAME.git${RST}"
echo
echo "别人拿到后的安装方式："
echo "  ${DIM}cd $REPO_NAME && ./scripts/install.sh${RST}"
