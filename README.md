# Sing-box Docker 一键部署脚本

基于 Docker 的 Sing-box 快速部署解决方案，提供交互式菜单操作，支持多协议配置，自动生成客户端配置文件。

## 📋 目录

- [功能特性](#功能特性)
- [支持协议](#支持协议)
- [系统要求](#系统要求)
- [快速开始](#快速开始)
- [老版本升级](#老版本升级)
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
  - Mihomo/Clash Meta 内核客户端（如 Clash Verge Rev、FlClash）
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

将该 URL 填入 Mihomo/Clash Meta 客户端的“订阅/配置 URL”即可。还需要在 VPS 防火墙和云厂商安全组中放行脚本显示的订阅 TCP 端口。

## 🔄 老版本升级

> **不要直接选择“安装部署 Sing-box”覆盖老版本。** 完整安装流程会重新生成 UUID、Reality 密钥、Short ID、证书和客户端配置，可能导致现有客户端立即失效。

推荐采用原地升级：保留正在使用的 Sing-box 配置和四个代理端口，只更新管理脚本，并在现有 Compose 中增加轻量订阅服务。这样防火墙通常只需新增一个订阅 TCP 端口。

### 升级原则

1. 先只读检查安装目录、容器、监听端口、配置文件和防火墙类型。
2. 备份 `setup.sh`、`docker-compose.yml`、`config/`、`certs/` 和当前防火墙规则。
3. 保留现有 UUID、Reality 密钥、Short ID、证书及代理端口。
4. 使用现有 `config/clash.yaml` 发布订阅；如果它与服务端配置不一致，应先根据现有配置修正。
5. 选择未占用的随机高位 TCP 端口作为订阅端口。
6. 先放行新端口，再启动和验证订阅服务；不要清空或整体重建防火墙。
7. 不得删除 SSH 端口及其他业务的防火墙规则。
8. 本机验证通过后，再从 VPS 外部或真实 Clash 客户端验证订阅 URL。

端口与防火墙协议对应关系：

| 用途 | 防火墙协议 |
|------|------------|
| VLESS Reality | TCP |
| VMess WebSocket | TCP |
| Hysteria2 | UDP |
| TUIC v5 | UDP |
| Clash URL 订阅 | TCP |

### 让 AI 帮助升级

可以把下面的任务说明直接发送给具有 VPS 终端权限的 AI：

```text
请帮我将 VPS 上现有的 easy-docker-singbox 原地升级到支持 Clash URL 订阅的新版本。

第一阶段只能做只读检查，请先汇报：
1. 项目安装目录、当前脚本版本和 Git 状态；
2. docker-compose.yml、config/config.json 和 config/clash.yaml 的状态；
3. 当前容器、监听端口及其 TCP/UDP 协议；
4. 当前防火墙类型、规则和 SSH 端口；
5. 是否还有需要人工修改的云厂商安全组；
6. 计划修改、保留和新增的文件、容器、端口及防火墙规则。

只读检查完成后先停下来，等我确认再修改。

确认后按以下要求执行：
- 先备份项目文件和防火墙规则，并提供备份路径与回滚命令；
- 不运行卸载，不执行 docker system prune，不清空或重置防火墙；
- 不直接运行会重新生成节点凭据的完整安装流程；
- 保留现有 Sing-box 配置、UUID、Reality 密钥、Short ID、证书和四个代理端口；
- 更新 setup.sh，并在现有 Compose 中增加 clash-subscription 服务；
- 使用 busybox:1.38.0，只读挂载 subscription 目录，使用非 root 用户，read_only=true、cap_drop=ALL、no-new-privileges=true；
- 使用现有 clash.yaml 作为订阅内容，生成至少 192 bit 的随机订阅令牌；
- 选择一个未占用的随机高位 TCP 端口，生成 http://VPS_IP:端口/随机令牌.yaml；
- 根路径不得列出订阅文件，将 URL 和令牌分别保存到 config/subscription.url 和 config/subscription.token，权限设为 600；
- 先新增订阅 TCP 端口的防火墙规则，再启动订阅服务；
- 保留 SSH 和所有无关服务的规则，不要直接删除旧端口规则；
- 如果必须更换代理端口或节点凭据，立即停止并说明会影响哪些客户端，等我确认。

完成后逐项验证：
1. sing-box 和 sing-box-subscription 容器均正常运行；
2. 原有四个代理端口仍按原协议监听；
3. VPS 本机能够下载订阅，且内容与 clash.yaml 完全一致；
4. Clash YAML 可以解析并包含预期节点；
5. 订阅 TCP 端口已放行，SSH 端口仍然放行；
6. 如果具备外部测试条件，从 VPS 外部测试订阅；否则请我用真实 Clash 客户端完成最终验证。

最后提供完整订阅 URL、端口清单、修改文件、增加的防火墙规则、验证结果、备份路径和回滚命令。不要仅凭容器启动成功就宣布完成。
```

如果决定完整重新部署，请先接受节点凭据可能发生变化、旧客户端需要重新导入配置这一影响。防火墙调整应遵循“先增加新规则并验证，再删除确认无用的旧规则”，不要直接用新规则覆盖全部现有配置。

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

### Clash 配置导入

推荐直接使用 URL 订阅：

1. 打开 Clash Verge Rev、FlClash 等 Mihomo/Clash Meta 客户端
2. 找到“订阅”或“配置”页面
3. 新增 URL 订阅，粘贴 `config/subscription.url` 中的链接
4. 更新并启用配置

也可以离线导入生成的 `clash.yaml`：

1. 打开客户端的“配置”页面
2. 选择从本地文件导入
3. 选择 `docker-singbox/config/clash.yaml`
4. 启用配置并选择节点

> 说明：订阅中包含 VLESS Reality、Hysteria2 和 TUIC 节点，需要 Mihomo/Clash Meta 内核；传统 Clash 内核无法完整识别这些协议。

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
