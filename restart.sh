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