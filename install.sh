#!/bin/sh

curl -fsSL https://tailscale.com/install.sh | sh

sudo tailscale up

sudo apt-get update

sudo apt-get install -y wget curl iputils-ping net-tools libcap2-bin haproxy

# 公式鍵のインポート
curl -fsSL https://nginx.org/keys/nginx_signing.key | sudo gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg

# Ubuntuのコードネームを確認（例: focal, jammy）
CODENAME=$(lsb_release -cs)

# nginx.org公式リポジトリを追加
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu $CODENAME nginx" | sudo tee /etc/apt/sources.list.d/nginx.list

# 優先度設定（aptが公式nginxを優先するように）
sudo tee /etc/apt/preferences.d/99nginx <<EOF
Package: *
Pin: origin nginx.org
Pin-Priority: 900
EOF

# パッケージリスト更新
sudo apt-get update

# nginxインストール
sudo apt-get install -y nginx

sudo setcap 'cap_net_bind_service=+ep' /usr/sbin/haproxy

printf "Enter Tailscale IPv4 for Minecraft Server: "
read ts_ip

cat <<EOF | sed "s/tailscale_ip/$ts_ip/" | sudo tee /etc/haproxy/haproxy.cfg > /dev/null
listen minecraft
    bind :25565
    mode tcp
    balance leastconn
    option log-health-checks
    option srvtcpka
    default-server inter 10s fall 1 rise 10
    option tcp-check
    server minecraft-backend tailscale_ip:25565 check-send-proxy send-proxy-v2
    acl too_fast fe_sess_rate gt 10
    tcp-request content reject if too_fast
EOF

echo "✅ haproxy.cfg updated with Tailscale IP: $ts_ip"

cat <<EOF | sed "s/tailscale_ip/$ts_ip/" | sudo tee /etc/nginx/nginx.conf > /dev/null
worker_processes 2;

events {
    worker_connections 1024;
}

stream {
    log_format proxy '$remote_addr [$time_local] '
                     '$protocol $status $bytes_sent $bytes_received '
                     '$session_time "$upstream_addr" '
                     '"$upstream_bytes_sent" "$upstream_bytes_received" "$upstream_connect_time"';

    upstream minecraft_udp_upstreams {
        server tailscale_ip:19132;
    }

    server {
        error_log /var/log/nginx/error.log debug;
        access_log /var/log/nginx/access.log proxy buffer=32k;
        listen 19132 udp;
        proxy_pass minecraft_udp_upstreams;
        proxy_timeout 120s;
        proxy_protocol on;
    }
}
EOF

echo "✅ /usr/local/etc/haproxy/haproxy.cfg and /etc/nginx/nginx.conf updated with Tailscale IP: $ts_ip"

if ! systemctl list-unit-files | grep -q "^nginx.service"; then
  echo "nginx.service not found. Creating service unit..."

  sudo tee /etc/systemd/system/nginx.service > /dev/null <<'EOF'
[Unit]
Description=A high performance web server and a reverse proxy server
After=network.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
fi

sudo systemctl restart nginx
sudo systemctl enable nginx

if systemctl list-unit-files | grep -q haproxy.service; then
    sudo systemctl restart haproxy
    sudo systemctl enable haproxy
    echo "✅ HAProxy service restarted"
else
    sudo /usr/sbin/haproxy -f /etc/haproxy/haproxy.cfg -D
    echo "✅ HAProxy started manually"
fi