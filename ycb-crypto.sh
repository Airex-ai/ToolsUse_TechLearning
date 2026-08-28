#!/usr/bin/env bash
# 通用项目加解密脚本（请放在项目外使用，用完可删）
#
# 用法:
#   YCB_CRYPTO_PASS='密码' /home/yuchaobo/ycb-crypto.sh --root <根目录> <命令> [子目录...]
#
# 示例:
#   /home/yuchaobo/ycb-crypto.sh --root /data/ycb_project status
#   YCB_CRYPTO_PASS='123.com' /home/yuchaobo/ycb-crypto.sh --root /data/ycb_project unlock
#   YCB_CRYPTO_PASS='123.com' /home/yuchaobo/ycb-crypto.sh --root /data/ycb_project unlock nora-1.5 lerobot conrft FluxVLA
#   YCB_CRYPTO_PASS='123.com' /home/yuchaobo/ycb-crypto.sh --root /data/ycb_project lock nora-1.5 lerobot conrft FluxVLA
#   /home/yuchaobo/ycb-crypto.sh --root /data/ycb_project migrate-vaults
set -euo pipefail

GCRYPTFS="${HOME}/bin/gocryptfs"
VAULT_BASE="/data/.d"
ROOT=""
DIFF_SHOW_LINES=40

# 旧 vault 迁移映射: 子目录 → /data/.d/<字母>
LEGACY_VAULT_MAP=(
  "conrft:a"
  "FluxVLA:b"
  "nora-1.5:c"
  "lerobot:d"
)

# vault 命名: /data/.d/<根目录键>__<子目录>
root_key() {
  echo "$ROOT" | sed 's|^/||' | tr '/' '__'
}

vault_path() {
  echo "${VAULT_BASE}/$(root_key)__${1}"
}

mount_dir()  { echo "${ROOT}/$1"; }
backup_dir() { echo "${ROOT}/.$1.bak"; }

die() { echo "错误: $*" >&2; exit 1; }

require_root() {
  [[ -n "$ROOT" ]] || die "必须指定 --root <根目录路径>"
  [[ -d "$ROOT" ]] || die "根目录不存在: $ROOT"
}

require_gocryptfs() {
  [[ -x "$GCRYPTFS" ]] || die "未找到 ${GCRYPTFS}"
}

is_mounted() { mountpoint -q "$1" 2>/dev/null; }

vault_initialized() {
  [[ -f "$(vault_path "$1")/gocryptfs.conf" ]]
}

# 是否已完成 migrate（vault 有实质数据，或当前为挂载点/已锁定）
is_migrated() {
  local p="$1" cipher mp kb
  cipher="$(vault_path "$p")"
  mp="$(mount_dir "$p")"
  vault_initialized "$p" || return 1
  is_mounted "$mp" && return 0
  [[ -d "$(backup_dir "$p")" ]] && return 0
  kb="$(du -sk "$cipher" 2>/dev/null | cut -f1)"
  [[ "${kb:-0}" -gt 1024 ]] && return 0   # vault > 1MB 视为已迁入数据
  return 1
}

get_password() {
  if [[ -n "${YCB_CRYPTO_PASS:-}" ]]; then
    PASSWORD="$YCB_CRYPTO_PASS"
    return 0
  fi
  read -r -s -p "请输入密码: " PASSWORD
  echo
  [[ -n "$PASSWORD" ]] || die "密码不能为空"
}

gocryptfs_init() {
  local cipher="$1"
  mkdir -p "$cipher"
  if [[ -n "${YCB_CRYPTO_PASS:-}${PASSWORD:-}" ]]; then
    printf '%s' "$PASSWORD" | "$GCRYPTFS" -passfile /dev/stdin -init "$cipher"
  else
    "$GCRYPTFS" -init "$cipher"
  fi
}

ensure_vault_init() {
  local p="$1" cipher
  cipher="$(vault_path "$p")"
  if vault_initialized "$p"; then
    return 0
  fi
  echo "[$p] vault 未初始化，自动 init → $cipher"
  gocryptfs_init "$cipher"
}

# 比对两个目录内容；一致返回 0，否则打印差异摘要并返回 1
compare_dirs() {
  local label="$1" src="$2" dst="$3"
  local diff_out rc
  echo "    比对[$label]: $src  ↔  $dst"
  set +e
  diff_out="$(diff -rq "$src" "$dst" 2>&1)"
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "    比对[$label]: 一致 ✓"
    return 0
  fi
  echo "    比对[$label]: 不一致 ✗" >&2
  if [[ -n "$diff_out" ]]; then
    echo "$diff_out" | head -n "$DIFF_SHOW_LINES" >&2
    local total
    total="$(echo "$diff_out" | wc -l)"
    if [[ "$total" -gt "$DIFF_SHOW_LINES" ]]; then
      echo "    ... 另有 $((total - DIFF_SHOW_LINES)) 行差异未显示" >&2
    fi
  fi
  return 1
}

cleanup_tmp_mount() {
  local tmp="$1"
  fusermount -u "$tmp" 2>/dev/null || true
  rmdir "$tmp" 2>/dev/null || true
}

# 锁定单个已 migrate 的项目（卸载 + 删除空挂载点）
lock_mounted_dir() {
  local p="$1" mp
  mp="$(mount_dir "$p")"

  if [[ ! -d "$mp" ]]; then
    echo "[$p] 已锁定"
    return 0
  fi
  if is_mounted "$mp"; then
    fusermount -u "$mp" || { echo "[$p] 卸载失败（可能被占用）" >&2; return 1; }
  fi
  if [[ -n "$(ls -A "$mp" 2>/dev/null)" ]]; then
    echo "[$p] 挂载点非空，未删除（异常，请检查）" >&2
    return 1
  fi
  rmdir "$mp"
  echo "[$p] 已锁定并隐藏"
  return 0
}

# 解析子目录：有参数用参数；否则根下非隐藏一级子目录 + 已有 vault（含已锁定）
resolve_subdirs() {
  local -n _out=$1
  shift
  _out=()

  if [[ $# -gt 0 ]]; then
    _out=("$@")
    return 0
  fi

  local entry name s rk glob
  shopt -s nullglob
  for entry in "${ROOT}"/*/; do
    name="$(basename "$entry")"
    [[ "$name" == .* ]] && continue
    _out+=("$name")
  done

  # 已锁定（目录不可见）但 vault 存在的子目录也纳入
  rk="$(root_key)"
  for glob in "${VAULT_BASE}/${rk}__"*; do
    [[ -f "${glob}/gocryptfs.conf" ]] || continue
    s="${glob#${VAULT_BASE}/${rk}__}"
    [[ " ${_out[*]} " == *" ${s} "* ]] && continue
    _out+=("$s")
  done
  shopt -u nullglob
}

gocryptfs_mount() {
  local cipher="$1" mp="$2"
  if [[ -n "${YCB_CRYPTO_PASS:-}${PASSWORD:-}" ]]; then
    printf '%s' "$PASSWORD" | "$GCRYPTFS" -passfile /dev/stdin -q "$cipher" "$mp"
  else
    "$GCRYPTFS" "$cipher" "$mp"
  fi
}

validate_subdir() {
  local sub="$1"
  [[ "$sub" != */* ]] || die "子目录名不能含 '/': $sub"
  [[ -d "$(mount_dir "$sub")" || -f "$(vault_path "$sub")/gocryptfs.conf" || -d "$(backup_dir "$sub")" ]] \
    || die "子目录不存在且无 vault: $sub"
}

# 若存在旧 a/b/c/d vault，自动重命名到新路径（幂等）
ensure_legacy_vaults() {
  [[ "$ROOT" == "/data/ycb_project" ]] || return 0

  local pair sub old new
  local did=0
  for pair in "${LEGACY_VAULT_MAP[@]}"; do
    sub="${pair%%:*}"
    old="${VAULT_BASE}/${pair##*:}"
    new="$(vault_path "$sub")"

    [[ -f "${old}/gocryptfs.conf" ]] || continue
    if [[ -e "$new" ]]; then
      echo "[$sub] 旧 vault $old 与新路径 $new 同时存在，请手动处理" >&2
      continue
    fi
    echo ">>> 自动迁移旧 vault [$sub]: $old → $new"
    mv "$old" "$new"
    ((did++)) || true
  done
  if [[ "$did" -gt 0 ]]; then
    echo "旧 vault 自动迁移完成: ${did} 个"
  fi
}

# ── 命令实现 ──────────────────────────────────────────
cmd_status() {
  ensure_legacy_vaults
  local subs=()
  resolve_subdirs subs "$@"
  [[ ${#subs[@]} -gt 0 ]] || die "根目录下未发现任何非隐藏子目录或 vault"

  echo "=== 加密状态 ==="
  printf "根目录: %s\n密文区: %s\n\n" "$ROOT" "$VAULT_BASE"

  local p mp cipher
  for p in "${subs[@]}"; do
    mp="$(mount_dir "$p")"
    cipher="$(vault_path "$p")"
    printf "%-16s " "$p"
    if ! vault_initialized "$p"; then
      if [[ ! -d "$mp" && ! -d "$(backup_dir "$p")" ]]; then
        echo "[未初始化，目录不存在]"
      else
        echo "[未初始化]"
      fi
    elif is_migrated "$p"; then
      echo -n "[已迁移 $(du -sh "$cipher" 2>/dev/null | cut -f1)] "
      if [[ -d "$mp" ]] && is_mounted "$mp"; then
        echo "已解锁 (挂载中)"
      elif [[ -d "$mp" ]]; then
        echo "目录存在但未挂载"
      else
        echo "已锁定 (不可见)"
      fi
    else
      echo -n "[仅init，明文未迁移] "
      echo "目录可见 ($(du -sh "$mp" 2>/dev/null | cut -f1))"
    fi
    if [[ -d "$(backup_dir "$p")" ]]; then
      echo "  └─ 明文备份: $(backup_dir "$p")"
    fi
    echo "  └─ vault: $cipher"
  done
  echo
  df -h "$VAULT_BASE" "$ROOT" 2>/dev/null | sed -n '1,3p'
}

cmd_init() {
  require_gocryptfs
  ensure_legacy_vaults
  local subs=()
  resolve_subdirs subs "$@"

  echo "根目录: $ROOT"
  echo "将初始化: ${subs[*]}"
  for p in "${subs[@]}"; do
    local cipher
    cipher="$(vault_path "$p")"
    if vault_initialized "$p"; then
      echo "[$p] 已初始化 → $cipher，跳过"
      continue
    fi
    mkdir -p "$cipher"
    echo ">>> init [$p] → $cipher"
    "$GCRYPTFS" -init "$cipher"
  done
  echo "init 完成"
}

cmd_migrate_one() {
  local p="$1"
  validate_subdir "$p"
  require_gocryptfs

  if is_migrated "$p"; then
    echo "[$p] 已 migrate，跳过"
    return 0
  fi

  local mp vault tmp bak
  mp="$(mount_dir "$p")"
  vault="$(vault_path "$p")"
  tmp="/tmp/gocryptfs-migrate-${p//\//_}-$$"
  bak="$(backup_dir "$p")"

  ensure_vault_init "$p"
  is_mounted "$mp" && die "[$p] 已挂载，先 lock"
  [[ -d "$bak" ]] && die "[$p] 备份已存在: $bak"
  [[ -d "$mp" ]] || die "[$p] 源目录不存在: $mp"

  echo ">>> migrate [$p] ($(du -sh "$mp" | cut -f1)) → $vault"
  echo "    可用空间: $(df -h "$VAULT_BASE" | awk 'NR==2{print $4}')"

  mkdir -p "$tmp"
  if ! gocryptfs_mount "$vault" "$tmp"; then
    rmdir "$tmp" 2>/dev/null || true
    die "[$p] 挂载临时目录失败"
  fi

  echo "    rsync 复制中..."
  if ! rsync -aH --info=progress2 "$mp/" "$tmp/"; then
    cleanup_tmp_mount "$tmp"
    die "[$p] rsync 失败，原目录未改动"
  fi
  sync

  # 复制后、替换前：明文 vs 临时挂载密文
  if ! compare_dirs "复制后" "$mp" "$tmp"; then
    cleanup_tmp_mount "$tmp"
    die "[$p] 复制后比对失败，原目录未改动，密文区可能有不完整数据"
  fi

  cleanup_tmp_mount "$tmp"

  echo "    保留明文备份，切换为加密挂载..."
  mv "$mp" "$bak"
  mkdir "$mp"
  if ! gocryptfs_mount "$vault" "$mp"; then
    # 尽量恢复明文目录
    rmdir "$mp" 2>/dev/null || true
    mv "$bak" "$mp"
    die "[$p] 正式挂载失败，已恢复明文目录"
  fi

  # 切换后：备份明文 vs 正式挂载
  if ! compare_dirs "迁移后" "$bak" "$mp"; then
    echo "[$p] 迁移后比对失败：加密挂载与明文备份不一致" >&2
    echo "    明文备份仍在: $bak" >&2
    echo "    当前挂载点: $mp （已挂载，请检查后决定是否保留）" >&2
    return 1
  fi

  echo "[$p] migrate 完成（已自动比对一致）"
  echo "    确认后可删备份: rm -rf $(printf '%q' "$bak")"
  return 0
}

cmd_migrate() {
  ensure_legacy_vaults
  get_password
  local subs=()
  resolve_subdirs subs "$@"
  for p in "${subs[@]}"; do
    cmd_migrate_one "$p" || true
    echo
  done
}

cmd_migrate_vaults() {
  [[ "$ROOT" == "/data/ycb_project" ]] \
    || die "旧 vault 迁移仅适用于 --root /data/ycb_project"

  local pair sub old new
  local ok=0 skip=0

  for pair in "${LEGACY_VAULT_MAP[@]}"; do
    sub="${pair%%:*}"
    old="${VAULT_BASE}/${pair##*:}"
    new="$(vault_path "$sub")"

    if [[ ! -f "${old}/gocryptfs.conf" ]]; then
      echo "[$sub] 旧 vault 不存在: $old，跳过"
      ((skip++)) || true
      continue
    fi
    if [[ -e "$new" ]]; then
      echo "[$sub] 目标已存在: $new，跳过（请先手动处理冲突）" >&2
      ((skip++)) || true
      continue
    fi

    echo ">>> 迁移 vault [$sub]: $old → $new"
    mv "$old" "$new"
    echo "[$sub] 完成"
    ((ok++)) || true
  done

  echo "vault 迁移完成: ${ok} 成功, ${skip} 跳过"
  if [[ "$ok" -gt 0 ]]; then
    echo "提示: 后续请使用新 vault 路径，旧 a/b/c/d 目录已移除"
  fi
}

cmd_unlock() {
  ensure_legacy_vaults
  local subs=()
  resolve_subdirs subs "$@"
  [[ ${#subs[@]} -gt 0 ]] || die "未发现子目录"

  get_password
  local ok=0 fail=0 skip=0 mp vault p
  for p in "${subs[@]}"; do
    mp="$(mount_dir "$p")"
    vault="$(vault_path "$p")"
    if ! vault_initialized "$p"; then
      echo "[$p] 未初始化，跳过"; ((skip++)) || true; continue
    fi
    if ! is_migrated "$p"; then
      echo "[$p] 未 migrate，仍为明文，跳过（无需 unlock）"; ((skip++)) || true; continue
    fi
    if is_mounted "$mp"; then
      echo "[$p] 已挂载"; ((ok++)) || true; continue
    fi
    mkdir -p "$mp"
    if gocryptfs_mount "$vault" "$mp"; then
      echo "[$p] 已解锁"; ((ok++)) || true
    else
      rmdir "$mp" 2>/dev/null || true
      echo "[$p] 解锁失败" >&2; ((fail++)) || true
    fi
  done
  unset PASSWORD
  echo "完成: ${ok} 成功, ${fail} 失败, ${skip} 跳过"
  [[ "$fail" -eq 0 ]]
}

cmd_lock() {
  require_gocryptfs
  ensure_legacy_vaults
  local subs=()
  resolve_subdirs subs "$@"
  [[ ${#subs[@]} -gt 0 ]] || die "无目标子目录"

  get_password

  local p ok=0 fail=0 mig=0
  set +e
  for p in "${subs[@]}"; do
    local mp
    mp="$(mount_dir "$p")"

    # 已 migrate 且已锁定
    if is_migrated "$p" && [[ ! -d "$mp" ]]; then
      echo "[$p] 已锁定"
      ((ok++)) || true
      continue
    fi

    # 未 migrate：有明文目录则自动 migrate（含复制后比对）
    if ! is_migrated "$p"; then
      if [[ ! -d "$mp" ]]; then
        echo "[$p] 无源目录且未 migrate，跳过" >&2
        ((fail++)) || true
        continue
      fi
      echo "[$p] 未 migrate，自动执行 migrate（含比对）+ lock ..."
      if ! cmd_migrate_one "$p"; then
        echo "[$p] 自动 migrate 失败" >&2
        ((fail++)) || true
        continue
      fi
      ((mig++)) || true
    fi

    # migrate 后或原本已 migrate：执行锁定
    if lock_mounted_dir "$p"; then
      ((ok++)) || true
    else
      ((fail++)) || true
    fi
  done
  set -e

  unset PASSWORD
  echo "完成: ${ok} 已锁定, ${mig} 新迁移, ${fail} 失败"
  [[ "$fail" -eq 0 ]]
}

usage() {
  cat <<'EOF'
通用项目加解密脚本

用法:
  /home/yuchaobo/ycb-crypto.sh --root <根目录> [--vault-base <密文根>] <命令> [子目录...]

必填:
  --root <路径>          项目根目录，如 /data/ycb_project

可选:
  --vault-base <路径>    密文存放根目录（默认 /data/.d）

命令:
  status         [子目录...]   查看状态
  init           [子目录...]   初始化 vault
  migrate        [子目录...]   迁移明文→加密（自动 diff 比对）
  migrate-vaults               将旧 a/b/c/d vault 迁移到新命名（仅 /data/ycb_project）
  unlock         [子目录...]   解锁
  lock           [子目录...]   锁定（未 migrate 则自动比对迁移后锁定）

子目录:
  可指定任意根目录下的一级子目录名；未指定时默认为根下全部非隐藏一级子目录
  （跳过以 "." 开头的文件夹），并包含已有 vault 的已锁定目录

vault 路径规则:
  /data/.d/<根目录键>__<子目录>
  例: --root /data/ycb_project 子目录 openpi
      → /data/.d/data__ycb_project__openpi

加密迁移流程 (migrate / lock 自动):
  1. rsync 明文 → 临时加密挂载
  2. diff -rq 比对复制前后（不一致则中止，明文不动）
  3. 明文改名为 .xxx.bak，正式挂载密文
  4. 再次 diff 备份与挂载（不一致则报错保留现场）

无交互示例:
  YCB_CRYPTO_PASS='123.com' /home/yuchaobo/ycb-crypto.sh --root /data/ycb_project unlock
  YCB_CRYPTO_PASS='123.com' /home/yuchaobo/ycb-crypto.sh --root /data/ycb_project unlock nora-1.5 lerobot
  YCB_CRYPTO_PASS='123.com' /home/yuchaobo/ycb-crypto.sh --root /data/ycb_project lock openpi lerobot
  /home/yuchaobo/ycb-crypto.sh --root /data/ycb_project status

注意:
  - 脚本放项目外，用完可删
  - 同一根目录下 vault 建议用同一密码
  - status/unlock/lock/migrate 会自动把旧 a/b/c/d 迁到新路径
  - migrate 前确认 /data 空间: df -h /data/.d
  - lock 对未 migrate 项目会自动 init → migrate（含比对）→ lock
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root)
        [[ $# -ge 2 ]] || die "--root 需要路径参数"
        ROOT="$(cd "$2" && pwd)"
        shift 2
        ;;
      --vault-base)
        [[ $# -ge 2 ]] || die "--vault-base 需要路径参数"
        VAULT_BASE="$2"
        shift 2
        ;;
      -h|--help|help)
        usage; exit 0
        ;;
      status|init|migrate|migrate-vaults|unlock|lock)
        CMD="$1"; shift; break
        ;;
      *)
        die "未知参数: $1（见 --help）"
        ;;
    esac
  done
  SUBDIRS=("$@")
}

main() {
  [[ $# -gt 0 ]] || { usage; exit 0; }
  local CMD SUBDIRS=()
  parse_args "$@"
  require_root

  case "$CMD" in
    status)         cmd_status "${SUBDIRS[@]}" ;;
    init)           cmd_init "${SUBDIRS[@]}" ;;
    migrate)        cmd_migrate "${SUBDIRS[@]}" ;;
    migrate-vaults) cmd_migrate_vaults ;;
    unlock)         cmd_unlock "${SUBDIRS[@]}" ;;
    lock)           cmd_lock "${SUBDIRS[@]}" ;;
  esac
}

main "$@"
