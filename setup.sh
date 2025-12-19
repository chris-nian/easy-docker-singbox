#!/bin/bash

# Sing-box Docker 一键部署向导
# 支持协议: Vless-reality, Vmess-ws, Hysteria2, Tuic-v5
# 支持功能: 安装、卸载、启动、停止、重启、查看状态

set -e

# 颜色定义
red(){ echo -e "\033[31m\033[01m$1\033[0m"; }
green(){ echo -e "\033[32m\033[01m$1\033[0m"; }
yellow(){ echo -e "\033[33m\033[01m$1\033[0m"; }
blue(){ echo -e "\033[36m\033[01m$1\033[0m"; }

# 检查root权限 (只在安装时检查)
check_root() {
    [[ $EUID -ne 0 ]] && red "请以root模式运行脚本" && exit 1
}

# 工作目录
WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$WORK_DIR/config"
CERTS_DIR="$WORK_DIR/certs"

mkdir -p "$CONFIG_DIR" "$CERTS_DIR"

# 检测系统架构
check_arch() {
    case $(uname -m) in
        aarch64) cpu=arm64;;
        x86_64) cpu=amd64;;
        *) red "不支持的架构: $(uname -m)" && exit 1;;
    esac
    green "检测到架构: $cpu"
}

# 检查Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        red "Docker 未安装，正在安装..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        red "Docker Compose 未安装，正在安装..."
        apt-get update && apt-get install -y docker-compose-plugin || \
        yum install -y docker-compose-plugin || \
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
    fi
    
    green "Docker 环境检查完成"
}

# 获取服务器IP
get_server_ip() {
    v4=$(curl -s4m5 icanhazip.com 2>/dev/null || echo "")
    v6=$(curl -s6m5 icanhazip.com 2>/dev/null || echo "")
    
    if [[ -n $v4 && -n $v6 ]]; then
        yellow "检测到双栈VPS:"
        echo "  IPv4: $v4"
        echo "  IPv6: $v6"
        read -p "$(yellow '使用哪个IP? [1]IPv4 [2]IPv6 (默认1): ')" ip_choice
        if [[ "$ip_choice" == "2" ]]; then
            server_ip="$v6"
            server_ip_bracket="[$v6]"
        else
            server_ip="$v4"
            server_ip_bracket="$v4"
        fi
    elif [[ -n $v4 ]]; then
        server_ip="$v4"
        server_ip_bracket="$v4"
    elif [[ -n $v6 ]]; then
        server_ip="$v6"
        server_ip_bracket="[$v6]"
    else
        red "无法获取服务器IP" && exit 1
    fi
    green "使用IP: $server_ip"
}

# 生成随机端口 (避免冲突)
random_port() {
    local port
    while true; do
        port=$(shuf -i 10000-65535 -n 1)
        if ! ss -tunlp | grep -q ":$port "; then
            echo $port
            return
        fi
    done
}

# 配置端口
setup_ports() {
    green "==================== 端口配置 ===================="
    
    read -p "$(yellow 'Vless-reality端口 (回车随机): ')" port_vless
    [[ -z $port_vless ]] && port_vless=$(random_port)
    blue "Vless-reality端口: $port_vless"
    
    read -p "$(yellow 'Vmess-ws端口 (回车随机): ')" port_vmess
    [[ -z $port_vmess ]] && port_vmess=$(random_port)
    blue "Vmess-ws端口: $port_vmess"
    
    read -p "$(yellow 'Hysteria2端口 (回车随机): ')" port_hy2
    [[ -z $port_hy2 ]] && port_hy2=$(random_port)
    blue "Hysteria2端口: $port_hy2"
    
    read -p "$(yellow 'Tuic-v5端口 (回车随机): ')" port_tuic
    [[ -z $port_tuic ]] && port_tuic=$(random_port)
    blue "Tuic-v5端口: $port_tuic"
}

# 生成密钥
generate_keys() {
    green "==================== 生成密钥 ===================="
    
    # UUID
    uuid=$(cat /proc/sys/kernel/random/uuid)
    blue "UUID: $uuid"
    
    # Reality密钥对
    if command -v sing-box &> /dev/null; then
        key_pair=$(sing-box generate reality-keypair)
    else
        # 使用docker临时生成
        key_pair=$(docker run --rm ghcr.io/sagernet/sing-box:latest generate reality-keypair 2>/dev/null || echo "")
    fi
    
    if [[ -n "$key_pair" ]]; then
        private_key=$(echo "$key_pair" | grep "PrivateKey" | awk '{print $2}')
        public_key=$(echo "$key_pair" | grep "PublicKey" | awk '{print $2}')
    else
        # 备用：使用openssl生成
        private_key=$(openssl rand -base64 32 | tr -d '\n')
        public_key="生成失败-请手动配置"
    fi
    
    blue "Reality Private Key: $private_key"
    blue "Reality Public Key: $public_key"
    
    # Short ID
    short_id=$(openssl rand -hex 8)
    blue "Short ID: $short_id"
    
    # 保存公钥供客户端使用
    echo "$public_key" > "$CONFIG_DIR/public.key"
}

# 生成自签证书
generate_self_signed_cert() {
    green "生成自签证书..."
    openssl ecparam -genkey -name prime256v1 -out "$CERTS_DIR/private.key" 2>/dev/null
    openssl req -new -x509 -days 36500 -key "$CERTS_DIR/private.key" -out "$CERTS_DIR/cert.pem" -subj "/CN=www.bing.com" 2>/dev/null
    blue "自签证书生成完成"
}

# 证书配置
setup_certificate() {
    green "==================== 证书配置 ===================="
    yellow "1: 使用自签证书 (回车默认)"
    yellow "2: 使用已有证书 (需提供路径)"
    read -p "请选择 [1-2]: " cert_choice
    
    if [[ "$cert_choice" == "2" ]]; then
        read -p "证书路径 (cert.pem): " cert_path
        read -p "私钥路径 (private.key): " key_path
        if [[ -f "$cert_path" && -f "$key_path" ]]; then
            cp "$cert_path" "$CERTS_DIR/cert.pem"
            cp "$key_path" "$CERTS_DIR/private.key"
            blue "证书已复制"
            tls_enabled=true
            tls_domain=$(openssl x509 -noout -subject -in "$CERTS_DIR/cert.pem" 2>/dev/null | sed 's/.*CN = //' | sed 's/,.*//')
            [[ -z $tls_domain ]] && tls_domain="www.bing.com"
        else
            red "证书文件不存在，使用自签证书"
            generate_self_signed_cert
            tls_enabled=false
            tls_domain="www.bing.com"
        fi
    else
        generate_self_signed_cert
        tls_enabled=false
        tls_domain="www.bing.com"
    fi
}

# Reality SNI 配置
setup_reality_sni() {
    green "==================== Reality SNI 配置 ===================="
    read -p "$(yellow 'Reality SNI域名 (回车默认apple.com): ')" reality_sni
    [[ -z $reality_sni ]] && reality_sni="apple.com"
    blue "Reality SNI: $reality_sni"
}

# 生成 docker-compose.yml
generate_docker_compose() {
    green "==================== 生成 docker-compose.yml ===================="
    
    cat > "$WORK_DIR/docker-compose.yml" <<'EOF'
version: "3.8"

services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: sing-box
    restart: always
    network_mode: host
    cap_add:
      - NET_ADMIN
      - NET_RAW
    volumes:
      - ./config:/etc/sing-box
      - ./certs:/etc/certs
    command: ["run", "-c", "/etc/sing-box/config.json"]
EOF
    
    blue "docker-compose.yml 已生成: $WORK_DIR/docker-compose.yml"
}

# 生成配置文件
generate_config() {
    green "==================== 生成配置文件 ===================="
    
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "::",
      "listen_port": ${port_vless},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${reality_sni}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${reality_sni}",
            "server_port": 443
          },
          "private_key": "${private_key}",
          "short_id": ["${short_id}"]
        }
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-ws",
      "listen": "::",
      "listen_port": ${port_vmess},
      "users": [
        {
          "uuid": "${uuid}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/${uuid}-vm",
        "max_early_data": 2048,
        "early_data_header_name": "Sec-WebSocket-Protocol"
      },
      "tls": {
        "enabled": ${tls_enabled},
        "server_name": "${tls_domain}",
        "certificate_path": "/etc/certs/cert.pem",
        "key_path": "/etc/certs/private.key"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2",
      "listen": "::",
      "listen_port": ${port_hy2},
      "users": [
        {
          "password": "${uuid}"
        }
      ],
      "ignore_client_bandwidth": false,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "/etc/certs/cert.pem",
        "key_path": "/etc/certs/private.key"
      }
    },
    {
      "type": "tuic",
      "tag": "tuic-v5",
      "listen": "::",
      "listen_port": ${port_tuic},
      "users": [
        {
          "uuid": "${uuid}",
          "password": "${uuid}"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "/etc/certs/cert.pem",
        "key_path": "/etc/certs/private.key"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": ["quic", "stun"],
        "outbound": "block"
      }
    ],
    "final": "direct"
  }
}
EOF
    blue "配置文件已生成: $CONFIG_DIR/config.json"
}

# 启动容器
start_container() {
    green "==================== 启动容器 ===================="
    cd "$WORK_DIR"
    
    # 停止旧容器
    docker compose down 2>/dev/null || docker-compose down 2>/dev/null || true
    
    # 启动新容器
    if docker compose up -d 2>/dev/null; then
        green "容器启动成功 (docker compose)"
    elif docker-compose up -d 2>/dev/null; then
        green "容器启动成功 (docker-compose)"
    else
        red "容器启动失败"
        exit 1
    fi
    
    sleep 2
    
    # 检查状态
    if docker ps | grep -q sing-box; then
        green "Sing-box 运行中"
    else
        red "Sing-box 启动失败，请检查日志: docker logs sing-box"
        exit 1
    fi
}

# 检查并安装 qrencode
check_qrencode() {
    if ! command -v qrencode &> /dev/null; then
        yellow "正在安装 qrencode..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y qrencode
        elif command -v yum &> /dev/null; then
            yum install -y qrencode
        elif command -v brew &> /dev/null; then
            brew install qrencode
        else
            yellow "无法自动安装 qrencode,二维码生成将跳过"
            return 1
        fi
    fi
    return 0
}

# 生成二维码文本
generate_qr_code() {
    local link="$1"
    if check_qrencode; then
        qrencode -t ANSIUTF8 "$link"
    else
        echo "(qrencode 未安装,跳过二维码生成)"
    fi
}

# 生成客户端配置
generate_client_config() {
    green "==================== 客户端配置 ===================="
    echo ""
    
    # Vless Reality
    vless_link="vless://${uuid}@${server_ip}:${port_vless}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${reality_sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#Vless-Reality"
    blue "========== Vless-Reality =========="
    echo "$vless_link"
    echo ""
    generate_qr_code "$vless_link"
    echo ""
    
    # Vmess WS
    vmess_json=$(cat <<EOF
{
  "v": "2",
  "ps": "Vmess-WS",
  "add": "${server_ip}",
  "port": "${port_vmess}",
  "id": "${uuid}",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "${tls_domain}",
  "path": "/${uuid}-vm",
  "tls": "$( [[ "$tls_enabled" == "true" ]] && echo "tls" || echo "")",
  "sni": "${tls_domain}"
}
EOF
)
    vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w 0)"
    blue "========== Vmess-WS =========="
    echo "$vmess_link"
    echo ""
    generate_qr_code "$vmess_link"
    echo ""
    
    # Hysteria2
    hy2_link="hysteria2://${uuid}@${server_ip}:${port_hy2}?insecure=1&sni=${tls_domain}#Hysteria2"
    blue "========== Hysteria2 =========="
    echo "$hy2_link"
    echo ""
    generate_qr_code "$hy2_link"
    echo ""
    
    # Tuic
    tuic_link="tuic://${uuid}:${uuid}@${server_ip}:${port_tuic}?congestion_control=bbr&alpn=h3&sni=${tls_domain}&udp_relay_mode=native&allow_insecure=1#Tuic-V5"
    blue "========== Tuic-V5 =========="
    echo "$tuic_link"
    echo ""
    generate_qr_code "$tuic_link"
    echo ""
    
    # 保存到文件(包含二维码)
    {
        echo "========== Vless-Reality =========="
        echo "$vless_link"
        echo ""
        if check_qrencode; then
            echo "二维码:"
            qrencode -t ANSIUTF8 "$vless_link"
        fi
        echo ""
        
        echo "========== Vmess-WS =========="
        echo "$vmess_link"
        echo ""
        if check_qrencode; then
            echo "二维码:"
            qrencode -t ANSIUTF8 "$vmess_link"
        fi
        echo ""
        
        echo "========== Hysteria2 =========="
        echo "$hy2_link"
        echo ""
        if check_qrencode; then
            echo "二维码:"
            qrencode -t ANSIUTF8 "$hy2_link"
        fi
        echo ""
        
        echo "========== Tuic-V5 =========="
        echo "$tuic_link"
        echo ""
        if check_qrencode; then
            echo "二维码:"
            qrencode -t ANSIUTF8 "$tuic_link"
        fi
        echo ""
        
        echo "========== 连接信息 =========="
        echo "服务器IP: $server_ip"
        echo "UUID: $uuid"
        echo "Reality Public Key: $public_key"
        echo "Reality Short ID: $short_id"
        echo ""
        echo "Vless-Reality端口: $port_vless"
        echo "Vmess-WS端口: $port_vmess"
        echo "Hysteria2端口: $port_hy2"
        echo "Tuic-V5端口: $port_tuic"
    } > "$CONFIG_DIR/client_links.txt"
    
    green "客户端链接已保存至: $CONFIG_DIR/client_links.txt"
    
    # 生成 Clash 配置文件
    generate_clash_config
}

# 生成 Clash 配置文件
generate_clash_config() {
    green "==================== 生成 Clash 配置 ===================="
    
    # 节点名称前缀
    local node_prefix="singbox-docker"
    local vless_name="vl-reality-${node_prefix}"
    local vmess_name="vm-ws-${node_prefix}"
    local hy2_name="hy2-${node_prefix}"
    local tuic_name="tu5-${node_prefix}"
    
    cat > "$CONFIG_DIR/clash.yaml" <<EOF
mixed-port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true

dns:
  enable: true
  listen: 0.0.0.0:1053
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.1.1.1/dns-query
    - https://dns.google/dns-query
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:
  - name: "${vless_name}"
    type: vless
    server: ${server_ip}
    port: ${port_vless}
    uuid: "${uuid}"
    flow: "xtls-rprx-vision"
    network: tcp
    udp: true
    tls: true
    servername: ${reality_sni}
    client-fingerprint: chrome
    reality-opts:
      public-key: "${public_key}"
      short-id: "${short_id}"

  - name: "${vmess_name}"
    type: vmess
    server: ${server_ip}
    port: ${port_vmess}
    uuid: "${uuid}"
    alterId: 0
    cipher: auto
    udp: true
    network: ws
    ws-opts:
      path: "/${uuid}-vm"
      headers:
        Host: "${tls_domain}"

  - name: "${hy2_name}"
    type: hysteria2
    server: ${server_ip}
    port: ${port_hy2}
    password: "${uuid}"
    sni: "${tls_domain}"
    alpn:
      - h3
    skip-cert-verify: true
    udp: true

  - name: "${tuic_name}"
    type: tuic
    server: ${server_ip}
    port: ${port_tuic}
    uuid: "${uuid}"
    password: "${uuid}"
    sni: "${tls_domain}"
    alpn:
      - h3
    udp-relay-mode: native
    congestion-controller: bbr
    skip-cert-verify: true

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "AUTO"
      - "${vless_name}"
      - "${hy2_name}"
      - "${tuic_name}"
      - "${vmess_name}"

  - name: "AUTO"
    type: url-test
    url: "http://www.gstatic.com/generate_204"
    interval: 300
    tolerance: 50
    proxies:
      - "${vless_name}"
      - "${hy2_name}"
      - "${tuic_name}"
      - "${vmess_name}"

  - name: 🍎Apple
    type: select
    proxies:
      - DIRECT
      - "${vless_name}"
      - "${hy2_name}"
      - "${tuic_name}"
      - "${vmess_name}"

  - name: "直连"
    type: select
    proxies:
      - DIRECT

rule-providers:
  reject:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/reject.txt"
    path: rule_provider/reject.yaml
    interval: 86400

  icloud:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/icloud.txt"
    path: rule_provider/icloud.yaml
    interval: 86400

  apple:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/apple.txt"
    path: rule_provider/apple.yaml
    interval: 86400

  direct:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/direct.txt"
    path: rule_provider/direct.yaml
    interval: 86400

  private:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/private.txt"
    path: rule_provider/private.yaml
    interval: 86400

  gfw:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/gfw.txt"
    path: rule_provider/gfw.yaml
    interval: 86400

  tld-not-cn:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/tld-not-cn.txt"
    path: rule_provider/tld-not-cn.yaml
    interval: 86400

  telegramcidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/telegramcidr.txt"
    path: rule_provider/telegramcidr.yaml
    interval: 86400

  cncidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/cncidr.txt"
    path: rule_provider/cncidr.yaml
    interval: 86400

  lancidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/lancidr.txt"
    path: rule_provider/lancidr.yaml
    interval: 86400

  applications:
    type: http
    behavior: classical
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/applications.txt"
    path: rule_provider/applications.yaml
    interval: 86400

rules:
  # 私网 IP 强制直连
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve

  # 直连
  - DOMAIN-SUFFIX,gpt2share.com,DIRECT
  - DOMAIN-SUFFIX,futunn.com,DIRECT
  - DOMAIN-SUFFIX,moomoo.com,DIRECT
  - DOMAIN-SUFFIX,futu5.com,DIRECT
  - DOMAIN-SUFFIX,futucdn.com,DIRECT
  - DOMAIN-SUFFIX,moomooapi.com,DIRECT

  # AI / 云服务：强制代理
  - DOMAIN-SUFFIX,anthropic.com,PROXY
  - DOMAIN-SUFFIX,claude.ai,PROXY
  - DOMAIN-SUFFIX,claudeusercontent.com,PROXY
  - DOMAIN-SUFFIX,anthropic.services,PROXY
  - DOMAIN-SUFFIX,anthropic.sh,PROXY
  - DOMAIN-SUFFIX,anthropic.tools,PROXY
  - DOMAIN-SUFFIX,anthropic.run,PROXY
  - DOMAIN-SUFFIX,cdn-claude.ai,PROXY
  - DOMAIN,static.anthropic.com,PROXY

  # OpenAI / ChatGPT
  - DOMAIN,ws.chatgpt.com,PROXY
  - DOMAIN,realtime.chatgpt.com,PROXY
  - DOMAIN-SUFFIX,chatgpt.com,PROXY
  - DOMAIN-SUFFIX,openai.com,PROXY
  - DOMAIN-SUFFIX,cdn.openai.com,PROXY
  - DOMAIN-SUFFIX,oaiusercontent.com,PROXY
  - DOMAIN-SUFFIX,openaiusercontent.com,PROXY

  # Google / Gemini
  - DOMAIN-SUFFIX,google.com,PROXY
  - DOMAIN-SUFFIX,googleapis.com,PROXY
  - DOMAIN-SUFFIX,gstatic.com,PROXY
  - DOMAIN-SUFFIX,googleusercontent.com,PROXY
  - DOMAIN-SUFFIX,ai.google.dev,PROXY
  - DOMAIN,generativelanguage.googleapis.com,PROXY
  - DOMAIN,notebooklm.google.com,PROXY
  - DOMAIN,generativeai.google.com,PROXY

  # Cloudflare / AWS / GitHub
  - DOMAIN-SUFFIX,cloudflare.com,PROXY
  - DOMAIN-SUFFIX,workers.dev,PROXY
  - DOMAIN-SUFFIX,cloudflareinsights.com,PROXY
  - DOMAIN-SUFFIX,cloudflareclient.com,PROXY
  - DOMAIN-SUFFIX,cloudflare-dns.com,PROXY
  - DOMAIN-SUFFIX,amazonaws.com,PROXY
  - DOMAIN-SUFFIX,s3.amazonaws.com,PROXY
  - DOMAIN-SUFFIX,cloudfront.net,PROXY
  - DOMAIN-SUFFIX,github.com,PROXY
  - DOMAIN-SUFFIX,githubusercontent.com,PROXY
  - DOMAIN,raw.githubusercontent.com,PROXY
  - DOMAIN-SUFFIX,jsdelivr.net,PROXY

  # Apple
  - IP-CIDR,17.0.0.0/8,🍎Apple,no-resolve
  - DOMAIN-SUFFIX,apple-dns.net,🍎Apple
  - DOMAIN,appleid.apple.com,🍎Apple
  - DOMAIN,idmsa.apple.com,🍎Apple
  - DOMAIN,setup.icloud.com,🍎Apple
  - DOMAIN,appleid.cdn-apple.com,🍎Apple
  - DOMAIN,albert.apple.com,🍎Apple
  - DOMAIN,gs.apple.com,🍎Apple
  - DOMAIN,ocsp.apple.com,🍎Apple
  - DOMAIN,push.apple.com,🍎Apple
  - DOMAIN,apns.apple.com,🍎Apple
  - DOMAIN-SUFFIX,icloud.com,🍎Apple
  - DOMAIN-SUFFIX,icloud-content.com,🍎Apple
  - DOMAIN-SUFFIX,me.com,🍎Apple
  - DOMAIN,gdmf.apple.com,🍎Apple
  - DOMAIN,mesu.apple.com,🍎Apple
  - DOMAIN,mdm.apple.com,🍎Apple

  # 广告拦截
  - RULE-SET,reject,REJECT

  # Apple / iCloud 规则集
  - RULE-SET,icloud,🍎Apple
  - RULE-SET,apple,🍎Apple

  # 国内直连
  - RULE-SET,direct,DIRECT

  # GFW / 非 CN TLD
  - RULE-SET,gfw,PROXY
  - RULE-SET,tld-not-cn,PROXY

  # Telegram
  - RULE-SET,telegramcidr,PROXY

  # 局域网/私有/应用直连
  - RULE-SET,private,DIRECT
  - RULE-SET,applications,DIRECT
  - RULE-SET,lancidr,DIRECT
  - GEOIP,LAN,DIRECT

  # 中国 IP 直连
  - RULE-SET,cncidr,DIRECT
  - GEOIP,CN,DIRECT

  # 最终兜底
  - MATCH,PROXY
EOF
    
    green "Clash 配置已生成: $CONFIG_DIR/clash.yaml"
    blue "可直接导入 Clash Verge 使用"
}

# 显示主菜单
show_main_menu() {
    clear
    green "============================================="
    green "   Sing-box Docker 管理脚本"
    green "============================================="
    echo ""
    
    # 检查安装状态
    if docker ps -a | grep -q sing-box; then
        if docker ps | grep -q sing-box; then
            green "当前状态: ✓ 运行中"
        else
            yellow "当前状态: ● 已停止"
        fi
    else
        blue "当前状态: ○ 未安装"
    fi
    
    echo ""
    echo "请选择操作:"
    echo ""
    echo "  1. 安装部署 Sing-box"
    echo "  2. 启动服务"
    echo "  3. 停止服务"
    echo "  4. 重启服务"
    echo "  5. 查看状态"
    echo "  6. 查看客户端配置"
    echo "  7. 卸载服务"
    echo "  0. 退出"
    echo ""
    read -p "$(yellow '请输入选项 [0-7]: ')" choice
    
    case $choice in
        1)
            check_root
            install_singbox
            ;;
        2)
            check_root
            start_service
            pause_and_return
            ;;
        3)
            check_root
            stop_service
            pause_and_return
            ;;
        4)
            check_root
            restart_service
            pause_and_return
            ;;
        5)
            show_status
            pause_and_return
            ;;
        6)
            show_client_config
            pause_and_return
            ;;
        7)
            check_root
            uninstall
            exit 0
            ;;
        0)
            echo ""
            green "再见!"
            exit 0
            ;;
        *)
            red "无效选项,请重新选择"
            sleep 2
            show_main_menu
            ;;
    esac
}

# 暂停并返回菜单
pause_and_return() {
    echo ""
    read -p "$(yellow '按回车键返回主菜单...')" 
    show_main_menu
}

# 显示客户端配置
show_client_config() {
    echo ""
    if [[ -f "$CONFIG_DIR/client_links.txt" ]]; then
        green "==================== 客户端配置 ===================="
        cat "$CONFIG_DIR/client_links.txt"
        echo ""
        green "Clash配置文件: $CONFIG_DIR/clash.yaml"
    else
        red "未找到客户端配置文件,请先安装部署"
    fi
}

# 卸载功能
uninstall() {
    clear
    echo ""
    yellow "=========================================="
    yellow "    Sing-box Docker 卸载程序"
    yellow "=========================================="
    echo ""
    
    read -p "$(red '确认卸载 Sing-box Docker? [y/N]: ')" confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "取消卸载"
        sleep 1
        show_main_menu
        return
    fi
    
    echo ""
    green "1. 停止并删除容器..."
    docker stop sing-box 2>/dev/null && green "   容器已停止" || yellow "   容器未运行"
    docker rm sing-box 2>/dev/null && green "   容器已删除" || yellow "   容器不存在"
    
    echo ""
    green "2. 删除 Docker 镜像..."
    docker rmi ghcr.io/sagernet/sing-box:latest 2>/dev/null && green "   镜像已删除" || yellow "   镜像不存在"
    
    echo ""
    green "3. 清理配置文件..."
    
    if [[ -d "$CONFIG_DIR" ]]; then
        rm -rf "$CONFIG_DIR"
        green "   已删除: $CONFIG_DIR"
    fi
    
    if [[ -d "$CERTS_DIR" ]]; then
        rm -rf "$CERTS_DIR"
        green "   已删除: $CERTS_DIR"
    fi
    
    if [[ -f "$WORK_DIR/docker-compose.yml" ]]; then
        rm -f "$WORK_DIR/docker-compose.yml"
        green "   已删除: docker-compose.yml"
    fi
    
    echo ""
    green "4. 清理 Docker 缓存..."
    docker system prune -f 2>/dev/null
    
    echo ""
    green "=========================================="
    green "   卸载完成!"
    green "=========================================="
    echo ""
    sleep 2
}

# 启动服务
start_service() {
    clear
    echo ""
    if docker ps -a | grep -q sing-box; then
        docker start sing-box
        green "✓ Sing-box 已启动"
        echo ""
        docker ps | grep sing-box
    else
        red "✗ Sing-box 容器不存在,请先安装部署"
    fi
    echo ""
}

# 停止服务
stop_service() {
    clear
    echo ""
    if docker ps | grep -q sing-box; then
        docker stop sing-box
        green "✓ Sing-box 已停止"
    else
        yellow "⚠ Sing-box 未运行"
    fi
    echo ""
}

# 重启服务
restart_service() {
    clear
    echo ""
    if docker ps -a | grep -q sing-box; then
        docker restart sing-box
        green "✓ Sing-box 已重启"
        echo ""
        docker ps | grep sing-box
    else
        red "✗ Sing-box 容器不存在,请先安装部署"
    fi
    echo ""
}

# 查看状态
show_status() {
    clear
    echo ""
    green "==================== Sing-box 状态 ===================="
    if docker ps | grep -q sing-box; then
        green "✓ Sing-box 运行中"
        echo ""
        docker ps | grep sing-box
        echo ""
        green "最近日志:"
        docker logs --tail 20 sing-box
    elif docker ps -a | grep -q sing-box; then
        yellow "⚠ Sing-box 已停止"
        echo ""
        docker ps -a | grep sing-box
    else
        red "✗ Sing-box 未安装"
    fi
    echo ""
}

# 显示使用帮助
show_help() {
    echo ""
    green "=========================================="
    green "   Sing-box Docker 管理脚本"
    green "=========================================="
    echo ""
    echo "用法: bash $0 [命令]"
    echo ""
    echo "命令:"
    echo "  (无参数)   - 安装并部署 Sing-box"
    echo "  start      - 启动服务"
    echo "  stop       - 停止服务"
    echo "  restart    - 重启服务"
    echo "  status     - 查看运行状态"
    echo "  uninstall  - 卸载服务"
    echo "  help       - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  bash $0           # 安装"
    echo "  bash $0 status    # 查看状态"
    echo "  bash $0 restart   # 重启服务"
    echo ""
}

# 安装主流程
install_singbox() {
    clear
    green "============================================="
    green "   Sing-box Docker 一键部署向导"
    green "   支持: Vless-reality, Vmess-ws, Hy2, Tuic"
    green "============================================="
    echo ""
    
    check_arch
    check_docker
    get_server_ip
    setup_ports
    generate_keys
    setup_certificate
    setup_reality_sni
    generate_docker_compose
    generate_config
    start_container
    generate_client_config
    
    echo ""
    green "============================================="
    green "   部署完成!"
    green "============================================="
    echo ""
    green "配置文件目录: $CONFIG_DIR"
    green "证书目录:     $CERTS_DIR"
    echo ""
    yellow "客户端链接: $CONFIG_DIR/client_links.txt"
    yellow "Clash配置:  $CONFIG_DIR/clash.yaml"
    echo ""
    
    pause_and_return
}

# 启动脚本入口
if [[ $EUID -ne 0 ]]; then
    yellow "提示: 部分操作需要 root 权限"
    echo ""
fi

show_main_menu
