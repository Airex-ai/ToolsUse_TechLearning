# Ubuntu项目加密/解密操作手册

> 原则：不在 `指定文件夹` 内存放脚本或工具，避免暴露加密意图。  
> 工具：gocryptfs（用户目录 `~/bin/gocryptfs`）  
> 密文存放：`~/.local/share/d/`（路径可自定义，勿放在项目内）

---

## 一、目录与项目对应关系

| 项目       | 挂载点（解锁后可见）                   | 密文目录（始终存在，加密态）可以调整为其他目录       |
| -------- | ---------------------------- | -------------------- |
| conrft   | `/data/ycb_project/conrft`   | `~/.local/share/d/a` |
| FluxVLA  | `/data/ycb_project/FluxVLA`  | `~/.local/share/d/b` |
| nora-1.5 | `/data/ycb_project/nora-1.5` | `~/.local/share/d/c` |
| lerobot  | `/data/ycb_project/lerobot`  | `~/.local/share/d/d` |

---

## 二、核心概念

### 1. 两种状态

| 状态     | 表现                        | 原理                |
| ------ | ------------------------- | ----------------- |
| 锁定（隐藏） | 项目目录从 `ls` 中消失，无法访问/打包/下载 | 卸载 FUSE 挂载点并删除空目录 |
| 解锁（可见） | 项目目录出现，内容可正常读写            | 用密码解密并挂载密文目录到原路径  |

### 2. 「迁移」的含义

不是把项目挪到其他文件夹。  
而是：把明文数据复制进加密库，原路径改为「需密码才出现的挂载点」。

迁移完成后：

- 解锁时路径不变（如 `/data/ycb_project/conrft`）
- 锁定后该路径消失
- 密文始终在 `~/.local/share/d/x`

---

## 三、无痕会话（每条命令前建议执行）

```bash
set +o history

export HISTFILE=/dev/null
```

| 步骤                          | 作用                   |
| --------------------------- | -------------------- |
| `set +o history`            | 关闭当前 shell 的命令历史记录   |
| `export HISTFILE=/dev/null` | 历史写入 `/dev/null`，不落盘 |

或使用独立无痕 shell：

```bash
env HISTFILE=/dev/null bash --noprofile --norc

set +o history
```

退出后恢复：`set -o history` 并 `unset HISTFILE`

---

## 四、一次性准备（仅首次）

### 步骤 1：安装 gocryptfs 到用户目录

```bash
mkdir -p ~/bin

curl -fsSL -o /tmp/g.tar.gz \

"https://github.com/rfjakob/gocryptfs/releases/download/v2.4.0/gocryptfs_v2.4.0_linux-static_amd64.tar.gz"

tar -xzf /tmp/g.tar.gz -C ~/bin gocryptfs

rm -f /tmp/g.tar.gz
```

| 作用                                       |
| ---------------------------------------- |
| 将 gocryptfs 装到 `~/bin`，不依赖 sudo，也不留在项目目录 |

### 步骤 2：创建密文存放目录

```bash
mkdir -p ~/.local/share/d/a ~/.local/share/d/b ~/.local/share/d/c ~/.local/share/d/
```

| 作用                                  |
| ----------------------------------- |
| gocryptfs 要求密文目录事先存在；`-init` 不会自动创建 |

### 步骤 3：初始化四个加密 vault

```bash
~/bin/gocryptfs -init ~/.local/share/d/a # conrft

~/bin/gocryptfs -init ~/.local/share/d/b # FluxVLA

~/bin/gocryptfs -init ~/.local/share/d/c # nora-1.5

~/bin/gocryptfs -init ~/.local/share/d/d # lerobot
```

| 步骤      | 作用                                   |
| ------- | ------------------------------------ |
| `-init` | 在空目录中创建加密文件系统元数据（含 `gocryptfs.conf`） |
| 交互设密码   | 生成主密钥；四个 vault 建议用同一密码，便于一次解锁        |

---

## 五、单项目迁移流程（以 conrft 为例）

其余项目替换 `P`、`CIPHER` 即可：

```bash
set +o history; export HISTFILE=/dev/null

P=conrft

ROOT=/data/ycb_project

CIPHER=~/.local/share/d/a

TMP=/tmp/m-$$
```

### 步骤 1：创建临时挂载点并挂载密文

```bash
mkdir -p "$TMP"

~/bin/gocryptfs "$CIPHER" "$TMP"
```

| 作用                                        |
| ----------------------------------------- |
| 将密文解密挂载到 `/tmp/m-$$`（`$$` 为当前进程 PID，避免冲突） |
| 输入密码后，临时目录内可读写加密区内容                       |

### 步骤 2：复制明文数据到加密区

```bash
rsync -aH "$ROOT/$P/" "$TMP/"

sync
```

| 参数/命令                | 作用               |
| -------------------- | ---------------- |
| `rsync -aH`          | 归档复制，保留权限、硬链接等   |
| `"$ROOT/$P/"` 末尾 `/` | 复制目录内容，不在目标下再套一层 |
| `sync`               | 刷盘，降低断电丢数据风险     |

### 步骤 3：卸载临时挂载点

```bash
fusermount -u "$TMP" && rmdir "$TMP"
```

| 作用                                     |
| -------------------------------------- |
| 卸载 FUSE，数据以加密形式写入 `~/.local/share/d/a` |
| 删除空临时目录                                |

### 步骤 4：保留明文备份

```bash
mv "$ROOT/$P" "$ROOT/.$P.bak"
```

| 作用                           |
| ---------------------------- |
| 原明文目录改名为 `.conrft.bak`（隐藏备份） |
| 验证无误后再删，避免误操作丢数据             |

### 步骤 5：在原路径创建挂载点并挂载

```bash
mkdir "$ROOT/$P"

~/bin/gocryptfs "$CIPHER" "$ROOT/$P"        #加密项目挂载操作
```

| 作用                                              |
| ----------------------------------------------- |
| 在原路径创建空目录作为挂载点                                  |
| 挂载后 `/data/ycb_project/conrft` 显示加密区内容，路径与迁移前一致 |

### 步骤 6：验证并清理备份（确认后执行）

# 对比文件数量或抽查关键文件

```bash
diff -rq "$ROOT/$P" "$ROOT/.$P.bak" | head
```

# 确认无误后删除明文备份

```bash
rm -rf "$ROOT/.$P.bak"
```

| 作用                      |
| ----------------------- |
| 确认加密挂载内容完整              |
| 删除 `.conrft.bak`，避免明文残留 |

---

## 六、日常操作

### 6.1 解锁（显示项目）

```bash
set +o history; export HISTFILE=/dev/null

R=/data/ycb_project

mkdir -p "$R/conrft" "$R/FluxVLA" "$R/nora-1.5" "$R/lerobot"

~/bin/gocryptfs ~/.local/share/d/a "$R/conrft"

~/bin/gocryptfs ~/.local/share/d/b "$R/FluxVLA"

~/bin/gocryptfs ~/.local/share/d/c "$R/nora-1.5"

~/bin/gocryptfs ~/.local/share/d/d "$R/lerobot"
```

| 步骤                       | 作用                     |
| ------------------------ | ---------------------- |
| `mkdir -p`               | 挂载点不存在时创建（锁定后已被删除）     |
| `gocryptfs CIPHER MOUNT` | 解密并挂载；每个 vault 需输入一次密码 |

只解锁单个项目时，只执行对应两行（`mkdir` + `gocryptfs`）。

### 6.2 锁定（隐藏项目）

```bash
set +o history; export HISTFILE=/dev/null

R=/data/ycb_project

for d in conrft FluxVLA nora-1.5 lerobot; do

fusermount -u "$R/$d" 2>/dev/null

rmdir "$R/$d" 2>/dev/null

done
```

| 步骤              | 作用                 |
| --------------- | ------------------ |
| `fusermount -u` | 卸载 FUSE，断开会话对目录的访问 |
| `rmdir`         | 删除空挂载点，目录从文件列表消失   |
| `2>/dev/null`   | 未挂载/已删除时忽略报错       |

注意：锁定前关闭占用该目录的进程（训练、IDE、终端 `cd` 等），否则卸载可能失败。

### 6.3 查看状态

```bash
set +o history; export HISTFILE=/dev/null

for d in conrft FluxVLA nora-1.5 lerobot; do

mp="/data/ycb_project/$d"

if mountpoint -q "$mp" 2>/dev/null; then

echo "$d: 已解锁（已挂载）"

elif [ -d "$mp" ]; then

echo "$d: 目录存在但未挂载"

else

echo "$d: 已锁定（不可见）"

fi

done
```

| 输出       | 含义              |
| -------- | --------------- |
| 已解锁（已挂载） | 可见、可访问          |
| 目录存在但未挂载 | 异常，可能是空目录或未成功挂载 |
| 已锁定（不可见） | 正常隐藏状态          |

---

## 八、操作速查

【首次】mkdir 密文目录 → gocryptfs -init（×4）

【迁移】挂临时点 → rsync → 卸载 → mv 备份 → mkdir → 挂载原路径

【解锁】mkdir 挂载点 → gocryptfs 密文→项目路径（×4 或按需）

【锁定】fusermount -u → rmdir（×4 或按需）

【无痕】set +o history; export HISTFILE=/dev/null


