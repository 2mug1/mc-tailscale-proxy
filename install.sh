#!/bin/sh

curl -fsSL https://tailscale.com/install.sh | sh

sudo tailscale up

sudo apt-get update

sudo apt-get install -y wget curl iputils-ping net-tools libcap2-bin haproxy nginx 

sudo setcap 'cap_net_bind_service=+ep' /usr/local/sbin/haproxy

printf "Enter Tailscale IPv4 for Minecraft Server: "
read ts_ip

# haproxy.cfg テンプレートの内容（直接ここに書き込み or 既存ファイルにテンプレ用意）
cat <<EOF | sed "s/tailscale_ip/$ts_ip/" | sudo tee /usr/local/etc/haproxy/haproxy.cfg > /dev/null
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

# nginx.conf テンプレートの内容（直接ここに書き込み or 既存ファイルにテンプレ用意）
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

# nginx systemdサービスユニットが無ければ作成する
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
    sudo /usr/local/sbin/haproxy -f /usr/local/etc/haproxy/haproxy.cfg -D
    echo "✅ HAProxy started manually"
fi