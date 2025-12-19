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
  - Clash Verge (可直接导入生成的 clash.yaml)
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

### 4. 获取客户端配置

部署完成后，客户端配置文件会自动保存至：

```
docker-singbox/config/
├── client_links.txt    # 客户端连接链接和二维码
├── clash.yaml          # Clash 配置文件
├── config.json         # Sing-box 服务端配置
└── public.key          # Reality 公钥
```

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
  2. 启动服务
  3. 停止服务
  4. 重启服务
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

#### 查看客户端配置

```bash
sudo bash setup.sh
# 选择 "6. 查看客户端配置"

# 或直接查看文件
cat docker-singbox/config/client_links.txt
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
│   └── public.key       # Reality 公钥
└── certs/               # 证书目录
    ├── cert.pem         # TLS 证书
    └── private.key      # TLS 私钥
```

### Clash 配置导入

生成的 `clash.yaml` 可直接导入 Clash Verge 使用：

1. 打开 Clash Verge
2. 点击 "配置" → "导入"
3. 选择 `docker-singbox/config/clash.yaml`
4. 启用配置并选择节点

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

## 🔧 故障排查

### 查看容器状态

```bash
docker ps -a | grep sing-box
```

### 查看实时日志

```bash
docker logs -f sing-box
```

### 查看最近日志

```bash
docker logs --tail 50 sing-box
```

### 重启容器

```bash
docker restart sing-box
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

## 📞 支持

如有问题或建议，欢迎：

- 提交 Issue
- 发起 Pull Request
- 查看项目文档

## 📄 许可证

本项目遵循相关开源协议。

---

**注意**: 本工具仅供学习和研究使用，请遵守当地法律法规。
