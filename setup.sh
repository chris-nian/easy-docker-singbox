#!/bin/bash

# Sing-box Docker 一键部署向导
# 支持协议: Vless-reality, Vmess-ws, Hysteria2, Tuic-v5
# 支持功能: 安装、卸载、启动、停止、重启、查看状态、Clash URL 订阅

# 移除 set -e，改用手动错误处理

# 颜色定义
red(){ echo -e "\033[31m\033[01m$1\033[0m"; }
green(){ echo -e "\033[32m\033[01m$1\033[0m"; }
yellow(){ echo -e "\033[33m\033[01m$1\033[0m"; }
blue(){ echo -e "\033[36m\033[01m$1\033[0m"; }

# 检查root权限 (只在安装时检查)
check_root() {
    if [[ $EUID -ne 0 ]]; then
        red "请以root模式运行脚本"
        read -p "按回车键返回主菜单..."
        show_main_menu
    fi
}

# 工作目录
WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$WORK_DIR/config"
CERTS_DIR="$WORK_DIR/certs"
SUBSCRIPTION_DIR="$WORK_DIR/subscription"

mkdir -p "$CONFIG_DIR" "$CERTS_DIR" "$SUBSCRIPTION_DIR"

# 兼容 Docker Compose 插件与旧版 docker-compose
compose() {
    if docker compose version &> /dev/null; then
        docker compose "$@"
    elif command -v docker-compose &> /dev/null; then
        docker-compose "$@"
    else
        return 1
    fi
}

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
        if ! ss -tunlp | grep -q ":$port " && \
           [[ "$port" != "${port_vless:-}" && "$port" != "${port_vmess:-}" && \
              "$port" != "${port_hy2:-}" && "$port" != "${port_tuic:-}" ]]; then
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

    read -p "$(yellow 'Clash订阅端口/TCP (回车随机): ')" subscription_port
    [[ -z $subscription_port ]] && subscription_port=$(random_port)
    blue "Clash订阅端口: $subscription_port"

    local ports=("$port_vless" "$port_vmess" "$port_hy2" "$port_tuic" "$subscription_port")
    local i j
    for i in "${!ports[@]}"; do
        if [[ ! "${ports[$i]}" =~ ^[0-9]+$ ]] || (( ports[$i] < 1 || ports[$i] > 65535 )); then
            red "端口必须是 1-65535 之间的整数，请重新配置"
            setup_ports
            return
        fi
        for ((j = i + 1; j < ${#ports[@]}; j++)); do
            if [[ "${ports[$i]}" == "${ports[$j]}" ]]; then
                red "所有代理端口和订阅端口必须互不重复，请重新配置"
                setup_ports
                return
            fi
        done
    done
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

    # Clash 订阅令牌（URL 中的不可猜测随机路径）
    subscription_token=$(openssl rand -hex 24)
    subscription_url="http://${server_ip_bracket}:${subscription_port}/${subscription_token}.yaml"
    
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
    
    cat > "$WORK_DIR/docker-compose.yml" <<EOF
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

  clash-subscription:
    image: busybox:1.38.0
    container_name: sing-box-subscription
    restart: always
    user: "65534:65534"
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    ports:
      - "${subscription_port}:${subscription_port}/tcp"
    volumes:
      - ./subscription:/www:ro
    command: ["httpd", "-f", "-p", "${subscription_port}", "-h", "/www"]
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
    compose down 2>/dev/null || true
    
    # 启动新容器
    if compose up -d; then
        green "容器启动成功"
    else
        red "容器启动失败"
        exit 1
    fi
    
    sleep 2
    
    # 检查状态
    if [[ "$(docker inspect -f '{{.State.Running}}' sing-box 2>/dev/null)" == "true" ]]; then
        green "Sing-box 运行中"
    else
        red "Sing-box 启动失败，请检查日志: docker logs sing-box"
        exit 1
    fi

    if [[ "$(docker inspect -f '{{.State.Running}}' sing-box-subscription 2>/dev/null)" == "true" ]]; then
        green "Clash 订阅服务运行中"
    else
        red "Clash 订阅服务启动失败，请检查日志: docker logs sing-box-subscription"
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
    vless_link="vless://${uuid}@${server_ip_bracket}:${port_vless}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${reality_sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#Vless-Reality"
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
    hy2_link="hysteria2://${uuid}@${server_ip_bracket}:${port_hy2}?insecure=1&sni=${tls_domain}#Hysteria2"
    blue "========== Hysteria2 =========="
    echo "$hy2_link"
    echo ""
    generate_qr_code "$hy2_link"
    echo ""
    
    # Tuic
    tuic_link="tuic://${uuid}:${uuid}@${server_ip_bracket}:${port_tuic}?congestion_control=bbr&alpn=h3&sni=${tls_domain}&udp_relay_mode=native&allow_insecure=1#Tuic-V5"
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
    publish_clash_subscription
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

proxies:
  - name: "${vless_name}"
    type: vless
    server: "${server_ip}"
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
    server: "${server_ip}"
    port: ${port_vmess}
    uuid: "${uuid}"
    alterId: 0
    cipher: auto
    udp: true
    tls: ${tls_enabled}
    servername: "${tls_domain}"
    network: ws
    ws-opts:
      path: "/${uuid}-vm"
      headers:
        Host: "${tls_domain}"

  - name: "${hy2_name}"
    type: hysteria2
    server: "${server_ip}"
    port: ${port_hy2}
    password: "${uuid}"
    sni: "${tls_domain}"
    alpn:
      - h3
    skip-cert-verify: true
    udp: true

  - name: "${tuic_name}"
    type: tuic
    server: "${server_ip}"
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

rule-providers:
  gfw:
    type: http
    behavior: domain
    # 上游文件名虽为 .txt，内容实际是 Clash YAML payload
    format: yaml
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/gfw.txt"
    path: rule_provider/gfw.txt
    interval: 86400

rules:
  # 本地域名和私网 IP 强制直连
  - DOMAIN,localhost,DIRECT
  - DOMAIN-SUFFIX,local,DIRECT
  - DOMAIN-SUFFIX,lan,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,169.254.0.0/16,DIRECT,no-resolve
  - IP-CIDR6,::1/128,DIRECT,no-resolve
  - IP-CIDR6,fc00::/7,DIRECT,no-resolve
  - IP-CIDR6,fe80::/10,DIRECT,no-resolve

  # 如有误判，可在 GFW 规则前添加少量人工覆盖规则，例如：
  - DOMAIN-SUFFIX,gpt2share.com,DIRECT
  - DOMAIN-SUFFIX,futunn.com,DIRECT
  - DOMAIN-SUFFIX,moomoo.com,DIRECT
  - DOMAIN-SUFFIX,futu5.com,DIRECT
  - DOMAIN-SUFFIX,futucdn.com,DIRECT
  - DOMAIN-SUFFIX,moomooapi.com,DIRECT

  # 仅 GFW 列表中的域名走代理
  - RULE-SET,gfw,PROXY

  # 黑名单模式：未命中 GFW 列表的流量全部直连
  - MATCH,DIRECT
EOF
    
    green "Clash 配置已生成: $CONFIG_DIR/clash.yaml"
    blue "可直接导入 FlClash、Stash 或 Mihomo/OpenClash 客户端使用"
}

# 发布并验证 Clash URL 订阅
publish_clash_subscription() {
    local old_token=""
    local subscription_file="$SUBSCRIPTION_DIR/${subscription_token}.yaml"
    local local_subscription_url="http://127.0.0.1:${subscription_port}/${subscription_token}.yaml"

    # 重新部署时只撤销上一次由本脚本生成的订阅 URL
    if [[ -f "$CONFIG_DIR/subscription.token" ]]; then
        old_token=$(tr -d '\r\n' < "$CONFIG_DIR/subscription.token")
        if [[ "$old_token" =~ ^[0-9a-f]{48}$ && "$old_token" != "$subscription_token" ]]; then
            rm -f "$SUBSCRIPTION_DIR/${old_token}.yaml"
        fi
    fi

    mkdir -p "$SUBSCRIPTION_DIR"
    chmod 755 "$SUBSCRIPTION_DIR"
    printf '%s\n' 'Clash subscription endpoint' > "$SUBSCRIPTION_DIR/index.html"
    chmod 644 "$SUBSCRIPTION_DIR/index.html"
    cp "$CONFIG_DIR/clash.yaml" "$subscription_file"
    chmod 644 "$subscription_file"
    printf '%s\n' "$subscription_token" > "$CONFIG_DIR/subscription.token"
    printf '%s\n' "$subscription_url" > "$CONFIG_DIR/subscription.url"
    chmod 600 "$CONFIG_DIR/subscription.token" "$CONFIG_DIR/subscription.url" "$CONFIG_DIR/client_links.txt"

    {
        echo ""
        echo "========== Clash URL 订阅 =========="
        echo "$subscription_url"
        echo "订阅端口(TCP): $subscription_port"
        echo "适用客户端: FlClash、Stash、Mihomo/OpenClash"
        echo "分流模式: GFW TXT 黑名单（命中代理，其余直连）"
    } >> "$CONFIG_DIR/client_links.txt"

    if curl -fsS --max-time 5 "$local_subscription_url" | cmp -s - "$CONFIG_DIR/clash.yaml"; then
        green "Clash 订阅本机校验成功"
    else
        red "Clash 订阅本机校验失败，请检查日志: docker logs sing-box-subscription"
        exit 1
    fi

    echo ""
    blue "========== Clash URL 订阅 =========="
    echo "$subscription_url"
    yellow "请在 VPS 防火墙/安全组放行 TCP 端口: $subscription_port"
    yellow "订阅 URL 含节点凭据，请勿公开分享"
}

# 显示主菜单
show_main_menu() {
    clear
    green "============================================="
    green "   Sing-box Docker 管理脚本"
    green "============================================="
    echo ""
    
    # 检查安装状态
    if command -v docker &> /dev/null && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx 'sing-box'; then
        if [[ "$(docker inspect -f '{{.State.Running}}' sing-box 2>/dev/null)" == "true" && \
              "$(docker inspect -f '{{.State.Running}}' sing-box-subscription 2>/dev/null)" == "true" ]]; then
            green "当前状态: ✓ 代理与订阅运行中"
        elif [[ "$(docker inspect -f '{{.State.Running}}' sing-box 2>/dev/null)" == "true" ]]; then
            yellow "当前状态: ⚠ 代理运行中，订阅服务异常"
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
        if [[ -f "$CONFIG_DIR/subscription.url" ]]; then
            green "Clash订阅链接: $(cat "$CONFIG_DIR/subscription.url")"
        fi
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
    
    # 检查Docker是否安装
    if ! command -v docker &> /dev/null; then
        red "Docker 未安装，无需卸载"
        echo ""
        sleep 2
        show_main_menu
        return
    fi
    
    read -p "$(red '确认卸载 Sing-box Docker? [y/N]: ')" confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "取消卸载"
        sleep 1
        show_main_menu
        return
    fi
    
    echo ""
    green "1. 停止并删除容器..."
    compose down 2>/dev/null && green "   代理与订阅容器已删除" || yellow "   容器不存在"
    
    echo ""
    green "2. 删除 Docker 镜像..."
    docker rmi ghcr.io/sagernet/sing-box:latest 2>/dev/null && green "   镜像已删除" || yellow "   镜像不存在"
    docker rmi busybox:1.38.0 2>/dev/null && green "   订阅服务镜像已删除" || yellow "   订阅服务镜像不存在或正在使用"
    
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

    if [[ -d "$SUBSCRIPTION_DIR" ]]; then
        rm -rf "$SUBSCRIPTION_DIR"
        green "   已删除: $SUBSCRIPTION_DIR"
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
    if [[ -f "$WORK_DIR/docker-compose.yml" ]]; then
        cd "$WORK_DIR" || return
        if compose up -d; then
            green "✓ Sing-box 与 Clash 订阅服务已启动"
        else
            red "✗ 服务启动失败"
            return
        fi
        echo ""
        docker ps --filter 'name=sing-box'
    else
        red "✗ docker-compose.yml 不存在,请先安装部署"
    fi
    echo ""
}

# 停止服务
stop_service() {
    clear
    echo ""
    if [[ -f "$WORK_DIR/docker-compose.yml" ]]; then
        cd "$WORK_DIR" || return
        compose stop
        green "✓ Sing-box 与 Clash 订阅服务已停止"
    else
        yellow "⚠ 服务未安装"
    fi
    echo ""
}

# 重启服务
restart_service() {
    clear
    echo ""
    if [[ -f "$WORK_DIR/docker-compose.yml" ]]; then
        cd "$WORK_DIR" || return
        if compose restart; then
            green "✓ Sing-box 与 Clash 订阅服务已重启"
        else
            red "✗ 服务重启失败"
            return
        fi
        echo ""
        docker ps --filter 'name=sing-box'
    else
        red "✗ 服务不存在,请先安装部署"
    fi
    echo ""
}

# 查看状态
show_status() {
    clear
    echo ""
    
    # 检查Docker是否安装
    if ! command -v docker &> /dev/null; then
        red "Docker 未安装"
        echo ""
        sleep 2
        return
    fi
    
    green "==================== Sing-box 状态 ===================="
    if [[ "$(docker inspect -f '{{.State.Running}}' sing-box 2>/dev/null)" == "true" ]]; then
        green "✓ Sing-box 运行中"
        echo ""
        docker ps --filter 'name=sing-box'
        echo ""
        green "最近日志:"
        docker logs --tail 20 sing-box 2>/dev/null || yellow "无法获取日志"
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx 'sing-box'; then
        yellow "⚠ Sing-box 已停止"
        echo ""
        docker ps -a | grep sing-box
    else
        red "✗ Sing-box 未安装"
    fi

    echo ""
    green "==================== Clash 订阅状态 ===================="
    if [[ "$(docker inspect -f '{{.State.Running}}' sing-box-subscription 2>/dev/null)" == "true" ]]; then
        green "✓ Clash 订阅服务运行中"
        if [[ -f "$CONFIG_DIR/subscription.url" ]]; then
            echo "订阅链接: $(cat "$CONFIG_DIR/subscription.url")"
        fi
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx 'sing-box-subscription'; then
        yellow "⚠ Clash 订阅服务已停止"
    else
        red "✗ Clash 订阅服务未安装"
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
    yellow "Clash订阅:  $subscription_url"
    yellow "放行端口:   TCP/$subscription_port"
    echo ""
    
    pause_and_return
}

# 启动脚本入口
if [[ $EUID -ne 0 ]]; then
    yellow "提示: 部分操作需要 root 权限"
    echo ""
fi

show_main_menu
