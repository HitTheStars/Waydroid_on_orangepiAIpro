#!/bin/bash
# arkplan/scripts/upload_release.sh — 把仓库外大件（镜像）传到 GitHub Releases
#
# 用法:
#   export GH_TOKEN=ghp_xxxxxxxx            # classic: repo / fine-grained: Contents=write
#   bash scripts/upload_release.sh --test   # 只建 release + 传一个 1KB 探针，验证 token 和链路
#   sudo -E bash scripts/upload_release.sh  # 完整上传（读 /root 下镜像，需要 root）
#
# 为什么不用 git：GitHub 单文件硬上限 100MB，system.img 1.86GiB 必然被拒。
# release 资源上限 2GiB/文件，system.img 1,994,985,472B 刚好塞得下（余量 ~153MB）。
set -u
REPO="HitTheStars/Waydroid_on_orangepiAIpro"
TAG="v1-20261027-images"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMG_DIR=${IMG_DIR:-/root/wd-img-backup-1027_2222}
API="https://api.github.com/repos/$REPO"
UP="https://uploads.github.com/repos/$REPO"
TEST=0; [ "${1:-}" = "--test" ] && TEST=1

# token 来源：环境变量优先，否则读 ~/.gh_token（chmod 600）
[ -z "${GH_TOKEN:-}" ] && [ -r "$HOME/.gh_token" ] && GH_TOKEN=$(tr -d ' \r\n' < "$HOME/.gh_token")
[ -z "${GH_TOKEN:-}" ] && { echo "缺 GH_TOKEN（或 ~/.gh_token）"; exit 1; }
export GH_TOKEN
command -v curl >/dev/null || { echo "缺 curl"; exit 1; }

api(){ curl -sS --http1.1 -H "Authorization: Bearer $GH_TOKEN" \
        -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@"; }

echo "== 1/4 校验 token =="
WHO=$(api https://api.github.com/user | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("login",""))' 2>/dev/null)
[ -n "$WHO" ] && echo "  ✅ 身份: $WHO" || { echo "  ❌ token 无效"; exit 1; }

echo "== 2/4 仓库与权限 =="
PERM=$(api "$API" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("permissions",{}).get("push",False))' 2>/dev/null)
[ "$PERM" = "True" ] && echo "  ✅ 对 $REPO 有写权限" || echo "  ⚠️ 读不到 push 权限（deploy key 方案下正常，继续）"

echo "== 3/4 建/取 release ($TAG) =="
REL_ID=$(api "$API/releases/tags/$TAG" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
if [ -z "$REL_ID" ]; then
  BODY="Waydroid 镜像快照（Orange Pi AIpro 20T · $(date +%F)）

- system.img 1,994,985,472B / vendor.img 421,629,952B
- 纯 arm64，无 AArch32 支持（本机内核无 AArch32 执行能力）
- 校验清单见仓库 state/assets.sha256，下载后：\`sha256sum -c assets.sha256\`
- 放回 \`$IMG_DIR/\` 后执行仓库 restore.sh"
  REL_ID=$(api -X POST "$API/releases" -d "$(python3 - "$TAG" "$BODY" <<'PY'
import json,sys
print(json.dumps({"tag_name":sys.argv[1],"name":"Waydroid 镜像快照 2026-10-27",
                  "body":sys.argv[2],"draft":False,"prerelease":False}))
PY
) " | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
  [ -n "$REL_ID" ] && echo "  ✅ 已创建 release id=$REL_ID" || { echo "  ❌ 创建失败（tag 可能已存在且被占用）"; exit 1; }
else
  echo "  ℹ️ 已存在 release id=$REL_ID，走补传"
fi

upload(){ # $1=本地文件 $2=资产名
  local f=$1 name=$2 sz rc
  sz=$(stat -c%s "$f" 2>/dev/null) || sz=$(sudo -n stat -c%s "$f" 2>/dev/null) || sz=0
  echo "  ↑ $name  ($(awk -v s=$sz 'BEGIN{printf "%.1f", s/1048576}') MB)"
  # 已存在同名资产则先删，避免 422
  OLD=$(api "$API/releases/$REL_ID/assets" | python3 -c "
import sys,json
for a in json.load(sys.stdin):
    if a['name']=='$name': print(a['id'])" 2>/dev/null)
  [ -n "${OLD:-}" ] && { api -X DELETE "$API/releases/assets/$OLD" >/dev/null; echo "    删除旧资产 $OLD"; }
  rm -f /tmp/rel_up.json
  # 关键：用 --upload-file 流式发送，--data-binary @file 会把整个文件读进内存（1.9G 直接 OOM）
  curl -sS --http1.1 --progress-bar -X POST \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Content-Type: application/octet-stream" \
    -H "Accept: application/vnd.github+json" \
    --expect100-timeout 30 --retry 5 --retry-all-errors --retry-delay 8 \
    --upload-file "$f" "$UP/releases/$REL_ID/assets?name=$name" -o /tmp/rel_up.json
  rc=$?
  if [ $rc -ne 0 ]; then echo "     ❌ curl 退出码 $rc（可重跑本脚本续传，已存在同名资产会先删）"; return 1; fi
  python3 - "$sz" <<'PY'
import json,sys
exp=int(sys.argv[1])
try:
    d=json.load(open("/tmp/rel_up.json"))
except Exception:
    print("     ❌ 无响应内容"); raise SystemExit(1)
got=d.get("size")
if d.get("state")=="uploaded" and got==exp:
    print(f"     ✅ {d['name']}  {got:,}B  {d['browser_download_url']}")
else:
    print(f"     ❌ 状态={d.get('state')} 期望{exp:,}B 实得{got}  {str(d.get('errors',''))[:200]}")
    raise SystemExit(1)
PY
}

SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

echo "== 4/4 上传 =="
if [ "$TEST" = "1" ]; then
  printf 'arkplan release upload probe %s\n' "$(date)" > /tmp/probe.txt
  upload /tmp/probe.txt probe.txt
  echo "探针通过 → release 页面: https://github.com/$REPO/releases/tag/$TAG"
  exit 0
fi
FAIL=0
for n in system vendor; do
  upload "$IMG_DIR/$n.img" "$n.img" || FAIL=1
done
echo
echo "== 复核 release 资产 =="
api "$API/releases/$REL_ID/assets" | python3 -c '
import sys,json
for a in json.load(sys.stdin):
    print("  {:14s} {:>13,}B  {}".format(a["name"], a["size"], a["state"]))'
[ $FAIL -ne 0 ] && { echo "有失败项，重跑本脚本会续传（同名资产先删再传）"; exit 1; }
echo "完成。校验方式（下载方）:"
echo "  sha256sum -c state/assets.sha256 --ignore-missing"
echo "release: https://github.com/$REPO/releases/tag/$TAG"
