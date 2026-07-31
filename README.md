# Sing-box Docker 一键部署脚本

基于 Docker 的 Sing-box 快速部署解决方案，提供交互式菜单操作，支持多协议配置，自动生成客户端配置文件。

## 📋 目录

- [功能特性](#功能特性)
- [支持协议](#支持协议)
- [系统要求](#系统要求)
- [快速开始](#快速开始)
- [使用说明](#使用说明)
- [配置文件](#配置文件)
- [常见问题](#常见问题)
- [故障排查](#故障排查)

## ✨ 功能特性

- 🚀 **一键部署** - 自动化安装配置，无需手动编辑配置文件
- 📱 **交互式菜单** - 友好的命令行界面，支持安装、启动、停止、重启、查看状态、卸载等操作
- 🔐 **多协议支持** - 同时配置 4 种主流代理协议
- 🎯 **自动生成配置** - 自动生成客户端连接链接、二维码和 Clash 配置文件
- 🔗 **Clash URL 订阅** - 部署后直接生成带随机令牌的订阅链接，可粘贴到客户端自动更新
- 🚦 **GFW 黑名单分流** - 仅 `gfw.txt` 规则命中的域名走代理，其他流量默认直连
- 🔄 **规则自动更新** - 客户端每天从公共规则源覆盖更新，不在订阅中内嵌或累积大型列表
- 🪶 **轻量发布** - 使用约 1–5 MB 的 BusyBox 官方镜像静态发布订阅，无数据库、面板或转换服务
- 🌐 **双栈支持** - 自动检测 IPv4/IPv6，支持用户选择
- 🔑 **密钥管理** - 自动生成 UUID、Reality 密钥对、Short ID 等
- 📦 **Docker 容器化** - 隔离环境，易于管理和迁移
- 🛡️ **证书管理** - 支持自签证书或自定义证书

## 🌍 支持协议

| 协议 | 说明 | 适用场景 |
|------|------|----------|
| **Vless-Reality** | 基于 REALITY 技术的 VLESS 协议，具有优秀的抗封锁能力 | 推荐首选，抗封锁能力强 |
| **Vmess-WS** | 基于 WebSocket 的 VMess 协议，兼容性好 | 通用场景，兼容性最佳 |
| **Hysteria2** | 基于 QUIC 的高性能协议，速度快 | 高速场景，游戏加速 |
| **Tuic-v5** | QUIC 协议，低延迟高性能 | 高性能需求场景 |

## 📦 系统要求

### 服务器端

- **操作系统**: Linux (Ubuntu/Debian/CentOS 等)
- **架构**: x86_64 或 aarch64 (ARM64)
- **权限**: Root 权限 (安装时需要)
- **环境**: Docker 和 Docker Compose (脚本会自动安装)

### 客户端

- **通用客户端**: 支持上述协议的任意客户端
- **推荐客户端**: 
  - Mihomo/Clash Meta 内核客户端（如 Clash Verge Rev、FlClash、OpenClash）
  - Stash
  - Shadowrocket (支持二维码扫描)
  - v2rayN/v2rayNG
  - Surge

## 🚀 快速开始

### 1. 下载脚本

```bash
# 下载脚本
wget https://raw.githubusercontent.com/chris-nian/easy-docker-singbox/refs/heads/main/setup.sh

# 或使用 curl
curl -O https://raw.githubusercontent.com/chris-nian/easy-docker-singbox/refs/heads/main/setup.sh

# 添加执行权限
chmod +x setup.sh
```

### 2. 运行安装

```bash
# 方式 1: 启动交互式菜单
sudo bash setup.sh

# 方式 2: 在菜单中选择 "1. 安装部署 Sing-box"
```

### 3. 配置向导

脚本会引导你完成以下配置：

1. **检测系统架构** - 自动识别 amd64 或 arm64
2. **检查 Docker** - 自动安装 Docker 和 Docker Compose（如未安装）
3. **获取服务器 IP** - 自动检测 IPv4/IPv6，支持手动选择
4. **端口配置** - 为每个协议配置端口（支持随机生成）
5. **生成密钥** - 自动生成 UUID、Reality 密钥对、Short ID
6. **证书配置** - 选择自签证书或自定义证书
7. **Reality SNI 配置** - 设置 Reality 伪装域名（默认 apple.com）
8. **发布并验证订阅** - 启动轻量静态服务，并从 VPS 本机拉取订阅进行一致性校验

### 4. 获取客户端配置

部署完成后，客户端配置文件会自动保存至：

```
docker-singbox/config/
├── client_links.txt    # 客户端连接链接和二维码
├── clash.yaml          # Clash 配置文件
├── subscription.url    # Clash 订阅链接
├── subscription.token  # 订阅随机令牌（请保密）
├── config.json         # Sing-box 服务端配置
└── public.key          # Reality 公钥
```

部署完成后，终端会显示类似下面的链接：

```text
http://203.0.113.10:12345/随机令牌.yaml
```

将该 URL 填入 FlClash、Stash 或 Mihomo/OpenClash 客户端的“订阅/配置 URL”即可。还需要在 VPS 防火墙和云厂商安全组中放行脚本显示的订阅 TCP 端口。

## 📖 使用说明

### 交互式菜单

运行脚本后会显示主菜单：

```
=============================================
   Sing-box Docker 管理脚本
=============================================

当前状态: ✓ 运行中

请选择操作:

  1. 安装部署 Sing-box
  2. 启动服务（代理 + 订阅）
  3. 停止服务（代理 + 订阅）
  4. 重启服务（代理 + 订阅）
  5. 查看状态
  6. 查看客户端配置
  7. 卸载服务
  0. 退出

请输入选项 [0-7]:
```

### 常用操作

#### 查看运行状态

```bash
sudo bash setup.sh
# 选择 "5. 查看状态"
```

#### 启动/停止/重启服务

```bash
sudo bash setup.sh
# 选择对应的菜单项
```

#### 查看客户端配置和订阅 URL

```bash
sudo bash setup.sh
# 选择 "6. 查看客户端配置"

# 或直接查看文件
cat docker-singbox/config/client_links.txt

# 只查看 Clash 订阅 URL
cat docker-singbox/config/subscription.url
```

#### 卸载服务

```bash
sudo bash setup.sh
# 选择 "7. 卸载服务"
```

完整卸载会：
- 停止并删除 Docker 容器
- 删除 Docker 镜像
- 清理所有配置文件和证书
- 清理 Docker 缓存

## 📁 配置文件

### 目录结构

```
docker-singbox/
├── setup.sh              # 部署脚本
├── docker-compose.yml    # Docker Compose 配置（自动生成）
├── config/               # 配置文件目录
│   ├── config.json      # Sing-box 服务端配置
│   ├── client_links.txt # 客户端连接信息
│   ├── clash.yaml       # Clash 客户端配置
│   ├── subscription.url # Clash 订阅链接
│   ├── subscription.token # 订阅随机令牌
│   └── public.key       # Reality 公钥
├── subscription/        # BusyBox 只读发布目录
│   └── <随机令牌>.yaml  # URL 实际返回的订阅配置
└── certs/               # 证书目录
    ├── cert.pem         # TLS 证书
    └── private.key      # TLS 私钥
```

### Clash/Stash 配置导入

推荐直接使用 URL 订阅：

1. 打开 FlClash、Stash、Clash Verge Rev 或 OpenClash 等客户端
2. 找到“订阅”或“配置”页面
3. 新增 URL 订阅，粘贴 `config/subscription.url` 中的链接
4. 更新并启用配置

也可以离线导入生成的 `clash.yaml`：

1. 打开客户端的“配置”页面
2. 选择从本地文件导入
3. 选择 `docker-singbox/config/clash.yaml`
4. 启用配置并选择节点

> 说明：订阅使用通用 `gfw.txt` 域名规则集，并包含 VLESS Reality、Hysteria2 和 TUIC 节点；请使用较新版本的 FlClash、Stash 或 Mihomo/OpenClash，传统 Clash 内核无法完整识别这些协议。

### GFW 黑名单分流

生成的订阅固定使用 `mode: rule`，规则顺序为：

1. 本地域名和私网地址直连
2. 少量人工直连覆盖规则
3. 命中 GFW TXT 规则集的域名走 `PROXY`
4. 其余所有流量由 `MATCH,DIRECT` 直连

GFW 规则来自 `Loyalsoldier/clash-rules` 的 `gfw.txt`。该文件名以 `.txt` 结尾，但内容是通用的 Clash YAML `payload`，所以配置中使用 `format: yaml`。客户端通过 `rule-providers` 每 86400 秒检查一次更新；成功更新时覆盖本地缓存，不会把每天的列表持续追加到内存或磁盘。配置不再加载 `reject.txt`、`direct.txt`、`tld-not-cn.txt`、中国 IP 等大型或与严格黑名单语义不符的规则集。

> 该分流由客户端执行。只有导入完整订阅并保持 `Rule` 模式时才会生效；仅复制单个节点链接，或者手动切换到 `Global` 模式，无法由 VPS 强制执行本地直连。

### 二维码扫描

如果系统安装了 `qrencode`，脚本会自动在终端显示二维码，也可以在 `client_links.txt` 中查看。

## ❓ 常见问题

### 1. 脚本提示 "请以 root 模式运行"？

安装、启动、停止等操作需要 root 权限：

```bash
sudo bash setup.sh
```

### 2. Docker 安装失败？

脚本会自动安装 Docker，如果失败可以手动安装：

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com | sh

# 启动 Docker
sudo systemctl enable docker
sudo systemctl start docker
```

### 3. 客户端无法连接？

检查以下几点：

1. **服务器防火墙** - 确保端口已开放
   ```bash
   # 查看配置的端口
   cat docker-singbox/config/client_links.txt
   
   # 开放端口（以 Ubuntu 为例）
   sudo ufw allow <端口号>
   ```

   订阅端口只使用 TCP；Hysteria2 和 TUIC 节点端口使用 UDP。若 VPS 还有云厂商安全组，也需要同步放行。

2. **服务状态** - 确认服务正在运行
   ```bash
   sudo bash setup.sh
   # 选择 "5. 查看状态"
   ```

3. **查看日志**
   ```bash
   docker logs sing-box
   ```

### 4. Vless-Reality 连接出现 "TLS handshake" 错误？

这通常是因为 public-key 或 short-id 不匹配：

1. 检查客户端配置的 public-key 和 short-id
2. 确认与服务器端配置一致（查看 `config/client_links.txt`）
3. 如果仍然失败，重新运行安装生成新的密钥对

### 5. 如何修改端口？

重新运行安装脚本会提示输入新端口：

```bash
sudo bash setup.sh
# 选择 "1. 安装部署 Sing-box"
# 在端口配置步骤输入新端口
```

### 6. 如何使用自定义证书？

在安装过程中选择证书配置时：

```
==================== 证书配置 ====================
1: 使用自签证书 (回车默认)
2: 使用已有证书 (需提供路径)
请选择 [1-2]: 2

证书路径 (cert.pem): /path/to/your/cert.pem
私钥路径 (private.key): /path/to/your/private.key
```

### 7. 二维码无法显示？

脚本需要 `qrencode` 工具生成二维码，会自动尝试安装。如果安装失败，可以手动安装：

```bash
# Ubuntu/Debian
sudo apt-get install qrencode

# CentOS/RHEL
sudo yum install qrencode

# macOS
brew install qrencode
```

或者直接复制 `client_links.txt` 中的连接链接到客户端。

### 8. Clash 订阅无法更新？

依次检查：

1. 菜单“查看状态”中 `Clash 订阅服务` 是否运行
2. `docker logs sing-box-subscription` 是否有报错
3. VPS 防火墙和云安全组是否已放行订阅 TCP 端口
4. 客户端是否使用 Mihomo/Clash Meta 内核

脚本部署时完成的是 VPS 本机订阅校验；公网可达性仍取决于防火墙、安全组和上游网络。

### 9. GFW 规则没有更新？

订阅配置和 GFW 规则是两个独立的更新请求。订阅导入成功后，客户端还需要访问：

```text
https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/gfw.txt
```

请检查客户端的 Rule Provider 页面或日志中 `gfw` 的更新时间。规则默认每 24 小时检查一次；首次下载失败时，可在网络恢复后手动刷新规则或重新更新订阅。

## 🔧 故障排查

### 查看容器状态

```bash
docker ps -a | grep sing-box
```

### 查看实时日志

```bash
docker logs -f sing-box

# 订阅服务日志
docker logs -f sing-box-subscription
```

### 查看最近日志

```bash
docker logs --tail 50 sing-box
```

### 重启容器

```bash
docker compose restart
```

### 手动启动容器

```bash
cd docker-singbox
docker-compose up -d
```

### 检查端口占用

```bash
# 查看端口是否被占用
ss -tunlp | grep <端口号>

# 或使用 netstat
netstat -tunlp | grep <端口号>
```

### 测试网络连通性

```bash
# 测试端口是否开放（从客户端执行）
telnet <服务器IP> <端口号>

# 或使用 nc
nc -zv <服务器IP> <端口号>
```

## 📝 配置说明

### Reality SNI 域名选择

Reality SNI 是伪装的目标域名，建议选择：

- 大型网站（如 apple.com、microsoft.com）
- 支持 TLSv1.3 的网站
- 访问稳定、不易变动的网站

### 端口选择建议

- **Vless-Reality**: 建议使用 443 或其他常见端口（如 8443）
- **Vmess-WS**: 可使用 80、443 或随机端口
- **Hysteria2/Tuic**: 建议使用随机高位端口（10000-65535）

### 性能优化建议

1. **BBR 加速** - 启用服务器 TCP BBR 拥塞控制算法
   ```bash
   echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
   echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
   sysctl -p
   ```

2. **系统限制** - 提升文件描述符限制
   ```bash
   ulimit -n 51200
   ```

## 🛡️ 安全建议

1. **定期更新** - 定期更新 Sing-box 镜像
   ```bash
   docker pull ghcr.io/sagernet/sing-box:latest
   # 然后重启服务
   ```

2. **密钥轮换** - 定期重新生成 UUID 和 Reality 密钥

3. **防火墙配置** - 只开放必要的端口

4. **日志监控** - 定期查看日志，发现异常流量

5. **保护订阅 URL** - URL 中的随机令牌等同于访问凭据，不要发布到群聊、论坛或公开仓库；重新部署会生成新令牌并撤销上一次由脚本生成的订阅路径

6. **按需升级 HTTPS** - 默认订阅为最简单、低资源占用的 HTTP 静态服务。HTTP 不防窃听；如网络环境不可信，请在已有域名和有效证书的前提下，通过 Caddy/Nginx 反向代理订阅端口并使用 HTTPS

## 📞 支持

如有问题或建议，欢迎：

- 提交 Issue
- 发起 Pull Request
- 查看项目文档

## 📄 许可证

本项目遵循相关开源协议。

---

**注意**: 本工具仅供学习和研究使用，请遵守当地法律法规。
