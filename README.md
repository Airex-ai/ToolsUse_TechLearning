# ubuntu_bug_fix

记录ubuntu系统的各种bug及解决方法

## Personal access tokens (classic)

### 安装搜狗输入法

1、更新源在终端执行 `sudo apt update`

![在终端执行 sudo apt update](https://ife.gtimg.com/build/client/official-website/assets/help5_44adebb.png)

2、安装fcitx输入法框架

1. 在终端输入` sudo apt install fcitx`

![1. 在终端输入 sudo apt install fcitx](https://ife.gtimg.com/build/client/official-website/assets/help6_265ae97.png)

2. 设置fcitx为系统输入法

点击左下角菜单选择语言支持，将语言选择为fcitx（如下图二）

![点击左下角菜单选择语言支持，将语言选择为fcitx（如下图二）](https://ife.gtimg.com/build/client/official-website/assets/help7_75a750e.png)![点击左下角菜单选择语言支持，将语言选择为fcitx（如下图二）](https://ife.gtimg.com/build/client/official-website/assets/help8_4616bd2.png)

3. 设置fcitx开机自启动

在终端执行`sudo cp /usr/share/applications/fcitx.desktop /etc/xdg/autostart/`

![在终端执行sudo cp /usr/share/applications/fcitx.desktop /etc/xdg/autostart/](https://ife.gtimg.com/build/client/official-website/assets/help9_6bb3da9.png)

4. 卸载系统ibus输入法框架

在终端执行 `sudo apt purge ibus`

![在终端执行 sudo apt purge ibus](https://ife.gtimg.com/build/client/official-website/assets/help10_e57ff8c.png)

3、安装搜狗输入法

1. 在官网下载搜狗输入法安装包，并安装，安装命令` sudo dpkg -i 安装包名`

![1. 在官网下载搜狗输入法安装包，并安装，安装命令 sudo dpkg -i 安装包名](https://ife.gtimg.com/build/client/official-website/assets/help11_17ff7e6.png)

2. 安装输入法依赖

在终端执行

```shell
sudo apt install libqt5qml5 libqt5quick5 libqt5quickwidgets5 qml-module-qtquick2 -y
sudo apt install libgsettings-qt1 -y
```

![安装输入法依赖](https://ife.gtimg.com/build/client/official-website/assets/help12_65c2433.png)

4、重启电脑、调出输入法

1.重启电脑

2.查看右上角，可以看到“搜狗”字样，在输入窗口即可且出搜狗输入法。

![查看右上角，可以看到“搜狗”字样，在输入窗口即可且出搜狗输入法](https://ife.gtimg.com/build/client/official-website/assets/help13_1c410df.png)

3. 没有“搜狗”字样，选择配置，将搜狗加入输入法列表即可

![3. 没有“搜狗”字样，选择配置，将搜狗加入输入法列表即可](https://ife.gtimg.com/build/client/official-website/assets/help14_90ff0c1.png)![3. 没有“搜狗”字样，选择配置，将搜狗加入输入法列表即可](https://ife.gtimg.com/build/client/official-website/assets/help15_09f3f5a.png)

至此，搜狗输入法安装完毕

![至此，搜狗输入法安装完毕](https://ife.gtimg.com/build/client/official-website/assets/help16_56116dc.png)



### 搜狗输入法无法在Chrome使用

```shell
sudo apt install fcitx5-frontend-gtk4
sudo shutdown -r now
```



### buntu WPS系统缺失字体symbol、wingdings、wingdings wingdings webding

```shell
git clone https://gitee.com/owlman/wps_fonts.git
cd wps_fonts
chmod 777 install_wps_fonts.sh 
./install_wps_fonts.sh
```





### 本地主机与服务器ROS2无法通信

- 两台主机在同一局域网内

- **主机A (当前主机)**: IP `192.168.1.106`
- **主机B (目标主机)**: IP `192.168.1.XXX` (需要确认实际IP)

#### 步骤1: 创建CycloneDDS配置文件

在新主机上创建配置文件：

```bash
# 创建配置文件
cat > ~/cyclonedds.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<CycloneDDS xmlns="https://cdds.io/config" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="https://cdds.io/config https://raw.githubusercontent.com/eclipse-cyclonedds/cyclonedds/master/etc/cyclonedds.xsd">
    <Domain id="any">
        <General>
            <NetworkInterfaceAddress>192.168.1.XXX</NetworkInterfaceAddress>
            <AllowMulticast>true</AllowMulticast>
            <MaxMessageSize>65500</MaxMessageSize>
            <EnableMulticastLoopback>true</EnableMulticastLoopback>
        </General>
        <Discovery>
            <ParticipantIndex>auto</ParticipantIndex>
            <MaxAutoParticipantIndex>100</MaxAutoParticipantIndex>
            <Peers>
                <Peer address="192.168.1.106"/>
                <Peer address="192.168.1.106:7400"/>
                <Peer address="192.168.1.XXX:7400"/>
            </Peers>
            <DefaultMulticastAddress>239.255.0.1</DefaultMulticastAddress>
            <Ports>
                <Base>7400</Base>
                <DomainGain>200</DomainGain>
                <ParticipantGain>2</ParticipantGain>
                <MulticastMetaOffset>0</MulticastMetaOffset>
                <MulticastDataOffset>10</MulticastDataOffset>
                <UnicastMetaOffset>1</UnicastMetaOffset>
                <UnicastDataOffset>11</UnicastDataOffset>
            </Ports>
        </Discovery>
        <Internal>
            <Watermarks>
                <WhcHigh>500</WhcHigh>
            </Watermarks>
        </Internal>
        <Tracing>
            <Verbosity>0</Verbosity>
        </Tracing>
    </Domain>
</CycloneDDS>
EOF
```

**重要**: 将上述配置文件中的 `192.168.1.XXX` 替换为新主机的实际IP地址！

#### 步骤2: 创建ROS2初始化脚本

```bash
# 创建初始化脚本
cat > ~/.ros2_init << 'EOF'
#!/bin/bash
# ROS2网络初始化脚本

# 获取本机IP地址（自动检测）
LOCAL_IP=$(hostname -I | awk '{print $1}')

# 设置ROS2网络环境变量
export ROS_DOMAIN_ID=24
export ROS_IP=$LOCAL_IP
export CYCLONEDDS_URI=file://$HOME/cyclonedds.xml

# 重启ROS2守护进程以应用新配置
echo "初始化ROS2网络配置..."
ros2 daemon stop >/dev/null 2>&1
ros2 daemon start >/dev/null 2>&1

echo "ROS2网络配置完成！"
echo "ROS_DOMAIN_ID=$ROS_DOMAIN_ID"
echo "ROS_IP=$ROS_IP"
echo "本机IP: $LOCAL_IP"
EOF

# 给脚本添加执行权限
chmod +x ~/.ros2_init
```

#### 步骤3: 配置全局环境变量

```bash
# 备份原bashrc
cp ~/.bashrc ~/.bashrc.backup

# 添加ROS2网络配置到bashrc
cat >> ~/.bashrc << 'EOF'

# >>> ROS2 Network Configuration >>>
# 配置ROS2跨机器节点发现
export ROS_DOMAIN_ID=24
export ROS_IP=$(hostname -I | awk '{print $1}')
export CYCLONEDDS_URI=file://$HOME/cyclonedds.xml

# 自动初始化ROS2网络配置（仅在交互式shell中）
if [[ $- == *i* ]] && command -v ros2 >/dev/null 2>&1; then
    ~/.ros2_init >/dev/null 2>&1
fi

# ROS2网络配置别名
alias ros2-init="~/.ros2_init"
alias ros2-network="echo 'ROS_DOMAIN_ID=$ROS_DOMAIN_ID, ROS_IP=$ROS_IP, CYCLONEDDS_URI=$CYCLONEDDS_URI'"
# <<< ROS2 Network Configuration <<<
EOF

# 重新加载bashrc
source ~/.bashrc
```

#### 步骤5: 配置防火墙（如果需要）

```bash
# 检查UFW状态
sudo ufw status

# 如果UFW启用，添加ROS2规则
sudo ufw allow 7400/udp  # ROS2发现端口
sudo ufw allow 7410/udp  # ROS2数据端口

# 或者完全禁用UFW进行测试（生产环境不推荐）
# sudo ufw disable
```





### 本地主机与docker容器ROS2无法通信

```sh
sudo docker run -dit --rm \
  --net=host \
  --ipc=host \
  --pid=host \
  --privileged \
  -v /dev:/dev \
  -v /dev/bus/usb:/dev/bus/usb \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -e DISPLAY=$DISPLAY \
  -v /etc/localtime:/etc/localtime:ro \
  -v $(pwd):/workspace \
  -v /dev/shm:/dev/shm\
  --name demo \
  gr00t_thor_ros2:latest 
```

如果使用了 `--net=host` 仍然看不到，请检查以下几点：

1. **ROS_DOMAIN_ID 一致性：** 确保宿主机以及 **Docker 容器内部** 的环境变量 `ROS_DOMAIN_ID` 是相同的（或者都没有设置，默认为 0）。

   Bash

   ```sh
   # 在容器内检查
   echo $ROS_DOMAIN_ID
   ```

2. **ROS_LOCALHOST_ONLY 变量：** 检查容器内是否意外设置了 `ROS_LOCALHOST_ONLY=1`。这会强制 ROS 2 只在本地回环接口通信。

   Bash

   ```sh
   # 确保它为空或 0
   unset ROS_LOCALHOST_ONLY
   ```

3. **防火墙：** 确保两台主机的防火墙（`ufw` 或 `iptables`）允许 UDP 通信，特别是 DDS 默认使用的端口。最简单的测试方法是暂时关闭防火墙：

   Bash

   ```sh
   sudo ufw disable
   ```



### 本地主机（公网）与服务器（内网）无法直接通信

#### 步骤1：笔记本与主机通过网线连接并能正常通信

#### 步骤2: 笔记本开启ssh服务

#### 步骤3：在本机上建立 SSH 动态代理

```sh
ssh -D 1080 -f -N -q username@192.168.55.101   #192.168.55.101是通过网线设置的ip
```

`-D 1080`：开启 SOCKS5 代理，监听本机 1080 端口

`-f`：后台运行

`-N`：不执行远程命令

`username`：笔记本的系统用户名

#### 步骤4：配置本机应用使用代理

```sh
# 安装 proxychains 工具
sudo apt install proxychains
# 编辑配置文件
sudo vim /etc/proxychains.conf
```

修改最后一行：

```sh
socks5  127.0.0.1 1080
```

然后通过 proxychains 访问内网服务器：

```sh
proxychains ssh user@192.168.4.72
```

#### 步骤5：通过设置ssh配置文件，使用编译器连接服务器

```
# 内网服务器配置（192.168.4.72）
Host 192.168.4.72
    HostName 192.168.4.72
    User your_server_username  # 替换为内网服务器的用户名（如 root）
    Port 22  # 内网服务器的 SSH 端口，默认 22
    ProxyCommand nc -X 5 -x 127.0.0.1:1080 %h %p  # 核心：走 SOCKS5 代理
```

`nc` 是 netcat 工具，Linux/macOS 一般自带，Windows 需安装 OpenSSH 并确保 nc 可用。

如果提示 `nc: invalid option -- X`，说明你的 nc 版本不支持 `-X`，安装 socat：

```sh
sudo apt install socat
```

```
ProxyCommand socat - PROXY:127.0.0.1:%h:%p,proxyport=1080,proxytype=socks5
```





### 本地主机共享VPN到远程服务器（单个命令行有效）

```sh
#=================本地
ssh -R 7890:127.0.0.1:7890 username@server_ip 
#-R [服务器端口]:127.0.0.1:[本地代理端口]，让服务器监听它的 7890 端口，并将所有发往该端口的流量通过 SSH 隧道转发到你本地主机的 7890 端口。

#===================服务器
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
```

```sh
#=================本地ssh配置文件
Host wit-A800
    HostName 124.221.114.84
    Port 3602
    User wit
    ForwardX11 yes
    ForwardX11Trusted yes
    ForwardAgent yes
    # 添加下面这一行：将服务器的 7897 转发到本地的 127.0.0.1:7897
    RemoteForward 7897 127.0.0.1:7897
    # 可选：如果端口被占用则报错提醒，方便排查
    ExitOnForwardFailure yes
   
#===================服务器.bashrc文件中
alias proxyon='export http_proxy=http://127.0.0.1:7897 https_proxy=http://127.0.0.1:7897'
alias proxyoff='unset http_proxy https_proxy'

source ~/.bashrc
proxyon
```


### 从服务器以断点方式下载文件
```
rsync -P -r -e "ssh -p 3602" wit@124.221.114.84:/media/wit/SSD_0/ycb/projectFile/openpi/checkpoints/pi05_pick0104_2views_full_finetune/1/25000 /home/airex/Downloads/openpi/checkpoints
```

### vscode设置python调试文件
launch.json:   对应的原始命令为“CUDA_VISIBLE_DEVICES=2,3,4,5  XLA_PYTHON_CLIENT_MEM_FRACTION=0.9 uv run scripts/train.py  pi05_Synapath_lerobot_v21 --exp-name=my_experiment --overwrite”

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "serve_policy: PICK_CUBE",
            "type": "debugpy",
            "request": "launch",
            "program": "${workspaceFolder}/scripts/serve_policy.py",
            "python": "${workspaceFolder}/.venv/bin/python",
            "justMyCode": false,      //加上可以跳到虚拟环境安装路径调试
            "args": [
                "--env", "PICK_CUBE",
                "--default_prompt", "Stack red cube on green cube, then stack yellow cube on blue cube | A robot is on a flat tabletop with four colored cubes: red, green, yellow, blue placed on the table."
            ],
            "env": {
                "CUDA_VISIBLE_DEVICES": "0,1,2,3"
            },
            "console": "integratedTerminal",
            "cwd": "${workspaceFolder}"
        },
        {
            "name": "serve_policy: train",
            "type": "debugpy",
            "request": "launch",
            "program": "${workspaceFolder}/scripts/train.py",
            "python": "${workspaceFolder}/.venv/bin/python",
            "args": [
                "pi05_Synapath_lerobot_v21",
                "--exp-name", "my_experiment",
                "--overwrite"
            ],
            "env": {
                "CUDA_VISIBLE_DEVICES": "2,3,4,5",
                "XLA_PYTHON_CLIENT_MEM_FRACTION": "0.9"
            },
            "console": "integratedTerminal",
            "justMyCode": false,
            "cwd": "${workspaceFolder}"
        },
    ]
}
```


### 调试jax框架时查看变量实际值
1. 在main函数顶端（第一行）插入jax.config.update("jax_disable_jit", True)  # DEBUG: 关闭JIT”
2. 调试中直接悬浮鼠标查看即可



### Codegraph的使用

在让大模型阅读整个项目时，在本地预先为代码库建立精确的符号关联和调用图，节约高达 90% 的探索时间。

```bash
1. npx @colbymchenry/codegraph
2. 重启客户端
3.  cd your-project
	codegraph init -i
```

可以通过项目文件夹下的`.codegraph`查看是否成功初始化，并检查IDE的MCP列表是否存在codegraph



## github提交远程仓库

------

#### 一、GitHub 网页建私有仓库

1. 登录 Airex-ai
2. 打开 https://github.com/new
3. Repository name：`lerobot_vla`
4. Visibility：Private
5. 不要勾选 README / .gitignore / License
6. Create repository
   地址：`https://github.com/Airex-ai/lerobot_vla.git`

------

#### 二、本机配置提交身份（本仓库即可）

```sh
cd /data/ycb_project/lerobot

git config user.name "Airex-ai"

git config user.email "2722683946@.com"
```

------

#### 三、从零初始化（适配旧版 Git）

```sh
git init

git checkout -b main

注意： 不要执行 `git init main`（会多出误建的 `main/` 空仓库）。若已存在：

rm -rf main
```

------

#### 四、忽略 data / outputs，再暂存

`.gitignore` 里已有 `outputs/`；对符号链接 `data`，需同时忽略 `data` 和 `data/`：*

```sh
grep -nE '^(data|outputs)' .gitignore
```

若已把 `data` 加进暂存区：

```sh
git rm --cached data
```

然后：

```sh
git add .

git status
```

核对：

- 有代码、文档、`src/` 等
- 没有 `data`、`outputs`、`.venv`、`.cache`、`main/`
- `.vscode/` 默认被忽略（`launch.json` 不会上传）

------

#### 五、首次提交

```sh
git commit -m "$(cat <<'EOF'

Initial snapshot: lerobot_vla v1.0.0

Archive current working tree as the first retained version.

EOF

)"
```

------

#### 六、关联远程并推送

```sh
git remote add origin https://github.com/Airex-ai/lerobot_vla.git

*# 或：git remote set-url origin https://github.com/Airex-ai/lerobot_vla.git*

git config http.postBuffer 524288000

git config http.version HTTP/1.1

git push -u origin main
```

密码处填 Personal Access Token，不是登录密码。
若再出现 `GnuTLS recv error (-110)`：换网络/代理。

------

#### 七、打 tag 并做 Release

```sh
git tag -a v1.0.0 -m "v1.0.0: first archived snapshot"

git push origin v1.0.0
```

网页：https://github.com/Airex-ai/lerobot_vla/releases/new

- Choose tag：`v1.0.0`
- Title：`v1.0.0`
- 写一句归档说明 → Publish release

------

#### 八、完成后核对

- 仓库为 Private
- `main` 上有首次提交
- 无 `data/`、`outputs/`
- 有 tag `v1.0.0` 与对应 Release
- 确认无误后，可删本地备份：`rm -rf .git.bak.hf`（可选）
