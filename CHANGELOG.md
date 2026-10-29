# Changelog

本项目的主要变更记录，格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [1.1.0] - 2026-10-29

### Changed

- `up` 不再每次都执行 `apt-get update` + `apt-get upgrade`：socat 已安装时直接跳过软件包步骤，
  缺失时只安装 socat，不影响系统其他软件包

### Added

- `-u/--update`：显式要求先更新软件源并升级已安装软件，再部署转发

## [1.0.0] - 2026-10-29

### Added

- 转发规则由命令行传入：`up -t <目标IP> <规则>...`，支持 `-f/--forward` 与位置参数两种写法
- 多网卡/多 IP：每条规则可指定监听 IP，同一端口可在不同网卡上分别转发，各自生成独立 systemd 单元
- 预检：监听 IP 是否存在、端口占用（按监听地址判断）、目标环路检测（本机网卡 IP + 公网 IP）、目标可达性提示
- 规则持久化到 `/etc/socat-forward/rules.conf`，供 `status` / `down` 读取
- 声明式部署：`up` 会自动清理不在新规则集内的遗留单元
- 命令与别名：`up`/`apply`/`install`、`status`/`list`/`ls`、`down`/`remove`/`uninstall`、`clean`/`reset`
- 短选项：`-t`、`-f`、`-n`、`-F`、`-p`、`-V`
- systemd 加固：`DynamicUser` + `CAP_NET_BIND_SERVICE` + `ProtectSystem` / `PrivateTmp` / `PrivateDevices`
- `--dry-run` 全流程预览；`--purge` 可同时卸载 socat
- Makefile（`make check` / `make install`）与 GitHub Actions ShellCheck CI
