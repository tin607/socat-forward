# socat-forward

> 在 Ubuntu Server 上用 socat + systemd 托管 TCP/UDP 端口转发。规则由命令行传入，支持多网卡/多 IP。

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Ubuntu%2022.04%2B-orange)
![Shell](https://img.shields.io/badge/shell-bash-4EAA25)
![Version](https://img.shields.io/badge/version-1.1.0-informational)

## 特性

- **规则参数化**：目标 IP、监听/目标端口全部通过命令行传入，不写死在脚本里
- **多网卡 / 多 IP**：每条规则可指定监听 IP；同一端口可在不同网卡上分别转发到不同目标
- **systemd 托管**：开机自启、异常自动重启、日志进 journal
- **安全加固**：服务以 `DynamicUser` 运行，仅保留 `CAP_NET_BIND_SERVICE`，并启用 sandbox 选项
- **预检保护**：监听 IP 是否存在、端口占用（按监听地址判断）、转发环路、目标可达性
- **声明式部署**：重跑自动清理旧单元，`--dry-run` 可完整预览；重跑不会升级系统软件包
- **可运维**：状态文件 + `status` / `down` 命令

## 快速开始

```bash
git clone <你的仓库地址> socat-forward
cd socat-forward

sudo make install        # 安装到 /usr/local/bin/socat-forward
sudo socat-forward up -t 203.0.113.10 \
  tcp:2222=22 tcp:443=443 udp:443=443 \
  tcp:50530=50530 tcp:50960=50960
```

首次部署建议先加 `-n/--dry-run` 预览：

```bash
sudo socat-forward up -n -t 203.0.113.10 \
  tcp:2222=22 tcp:443=443 udp:443=443 \
  tcp:50530=50530 tcp:50960=50960
```

不想安装也可以直接运行 `sudo bin/socat-forward ...`。

> 文档中的 IP 均为示例占位：`203.0.113.0/24`、`198.51.100.0/24` 是 RFC 5737 文档保留地址，`192.168.1.0/24` 为常见内网段。请替换成你自己的实际地址。

## 命令

| 命令 | 别名 | 说明 |
| --- | --- | --- |
| `up` | `apply`、`install` | 部署并启动转发（缺少 socat 时自动安装，不升级系统） |
| `status` | `list`、`ls` | 查看已部署规则、服务状态与监听情况 |
| `down` | `remove`、`uninstall` | 删除已部署的转发（按状态文件） |
| `clean` | `reset` | 清除所有 `socat-fwd-*` 单元（含遗留单元） |
| `-V` / `--version` | | 显示版本 |
| `-h` / `--help` | | 显示帮助 |

## 选项

| 选项 | 说明 |
| --- | --- |
| `-t, --target <IP>` | 目标 IP（规则里没写目标 IP 时使用） |
| `-f, --forward <规则>` | 转发规则，可重复；也可以直接写成位置参数 |
| `-n, --dry-run` | 只打印将要执行的操作，不做任何修改 |
| `-u, --update` | 先 `apt-get update` 并升级已安装软件，再部署（默认不做系统升级） |
| `-F, --force` | 跳过监听 IP 不存在 / 端口占用 / 目标为本机的检查 |
| `-p, --purge` | `down` / `clean` 时同时卸载 socat 软件包 |

## 规则格式

```
协议:[监听IP:]监听端口=[目标IP:]目标端口
```

- `协议`：`tcp` 或 `udp`
- 省略监听 IP：绑定 `0.0.0.0`（所有网卡）
- 省略目标 IP：使用 `-t/--target` 的值
- 如果每条规则都写了目标 IP，可以完全不传 `--target`

| 规则 | 含义 |
| --- | --- |
| `tcp:2222=22` | `0.0.0.0:2222` → `<target>:22` |
| `udp:443=443` | `0.0.0.0:443/udp` → `<target>:443` |
| `tcp:192.168.1.10:8080=198.51.100.20:80` | 只监听网卡 IP `192.168.1.10:8080` → `198.51.100.20:80` |
| `tcp:127.0.0.1:9000=22` | 仅本机回环可访问 |

> 分隔符用 `=`，不要用 `->`：shell 会把 `>` 当成输出重定向，规则会被截断并生成多余文件。
> 加了引号的 `'tcp:2222->22'` 仍兼容，但不推荐。

### 多网卡 / 多 IP 示例

```bash
sudo socat-forward up -t 203.0.113.10 \
  tcp:2222=22 \
  udp:443=443 \
  tcp:192.168.1.10:8080=198.51.100.20:80 \
  tcp:192.168.1.11:8080=198.51.100.21:80
```

同一端口 `8080` 在两块网卡上分别监听、各自转发。每个监听端点生成一个独立服务：

- 通配监听：`socat-fwd-<端口>-<协议>.service`
- 指定 IP：`socat-fwd-<端口>-<协议>-<IP 中的点换成横线>.service`

## 工作方式

1. 校验规则：协议、端口、IPv4、重复监听端点
2. 预检（`-F` 可跳过后三项）：监听 IP 是否在本机、目标是否为本机（环路）、端口是否被占用
3. 确保 `socat` 可用：已安装则跳过，缺失时才 `apt-get update` 并安装；加 `-u/--update` 才会顺带升级系统软件包（非交互，冲突配置保留本机版本）
4. 生成并启动 systemd 单元，清理不在本次规则里的旧单元（`up` 是声明式的）
5. 规则写入状态文件 `/etc/socat-forward/rules.conf`
6. 校验服务状态与监听，并直连目标端口给出提示

端口占用按监听地址判断：别的网卡 IP 上的同端口服务不算冲突；`0.0.0.0` 上的监听会与指定 IP 的规则冲突。

## 日常运维

```bash
# 查看已部署规则与状态
sudo socat-forward status

# 看日志
journalctl -u 'socat-fwd-*' -f

# 重启单个转发
sudo systemctl restart socat-fwd-443-tcp

# 修改规则：带上新的规则重跑 up 即可，旧单元会自动清理
sudo socat-forward up -t 203.0.113.10 tcp:2222=22 udp:443=443
```

## 卸载

```bash
# 删除已部署的转发（读取状态文件，保留状态文件外的单元）
sudo socat-forward down

# 清除所有 socat-fwd 单元（含遗留单元与 wants 符号链接）
sudo socat-forward clean

# 同时卸载 socat 软件包
sudo socat-forward clean -p
```

## 注意事项

- **仅 IPv4**：规则与监听均为 IPv4（`TCP4`/`UDP4`），IPv6 客户端无法连接。
- **用户态转发**：socat 是普通进程转发，不修改 iptables/nftables，也不需要开启 `net.ipv4.ip_forward`；高流量场景建议改用 nginx stream / haproxy / iptables。
- **UDP 会话**：以 `-T 300` 回收空闲 UDP 会话，可用环境变量 `UDP_IDLE_TIMEOUT` 调整。
- **监听 IP 校验**：监听 IP 必须已配置在本机网卡上。阿里云公网 EIP 是 NAT 的，不在网卡上，不能直接作为监听 IP，请监听 `0.0.0.0` 或私网 IP。
- **环路防护**：目标等于本机任一网卡 IP 或本机公网 IP 时会被拦截。
- **端口占用**：端口被 docker-proxy 等占用时脚本会拒绝执行；`-F` 可跳过检查，但转发通常会启动失败。
- **云安全组**：入方向需放行所有监听端口对应的 tcp/udp。
- **状态文件**：`/etc/socat-forward/rules.conf` 记录已部署规则；`clean` 会一并删除。

## 开发

```bash
make check     # bash -n + shellcheck（未安装 shellcheck 时自动跳过）
```

仓库结构：

```
bin/socat-forward            主脚本（安装后命令名为 socat-forward）
Makefile                     make check / install / uninstall
.github/workflows/ci.yml     GitHub Actions：语法检查 + ShellCheck
README.md
CHANGELOG.md
LICENSE
```

## License

[MIT](LICENSE) © 2026 win
