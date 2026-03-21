#!/bin/bash
# ============================================================
# 09_web_server_security.sh — Nginx security headers + rate limiting
# Adjust for Apache if not using Nginx.
# ============================================================
set -euo pipefail
echo "[09] Web Server Security Hardening"

# Install Nginx if not present
if ! command -v nginx &>/dev/null; then
  apt-get install -y nginx
fi

# ── Nginx: security-focused global config ─────────────────
cat > /etc/nginx/conf.d/security.conf <<'EOF'
# ── Hide Nginx version ────────────────────────────────────
server_tokens off;

# ── Security headers ──────────────────────────────────────
add_header X-Frame-Options              "SAMEORIGIN"            always;
add_header X-Content-Type-Options       "nosniff"               always;
add_header X-XSS-Protection             "1; mode=block"         always;
add_header Referrer-Policy              "strict-origin-when-cross-origin" always;
add_header Permissions-Policy           "geolocation=(), microphone=(), camera=()" always;
add_header Content-Security-Policy      "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none';" always;
add_header Strict-Transport-Security    "max-age=63072000; includeSubDomains; preload" always;
add_header X-Permitted-Cross-Domain-Policies "none" always;

# ── Rate limiting zones ───────────────────────────────────
limit_req_zone $binary_remote_addr zone=general:10m  rate=10r/s;
limit_req_zone $binary_remote_addr zone=api:10m      rate=5r/s;
limit_req_zone $binary_remote_addr zone=login:10m    rate=1r/s;
limit_conn_zone $binary_remote_addr zone=perip:10m;

# ── Connection limits ─────────────────────────────────────
limit_conn perip 20;

# ── Buffer overflow protection ────────────────────────────
client_body_buffer_size     1K;
client_header_buffer_size   1k;
client_max_body_size        10m;
large_client_header_buffers 2 1k;

# ── Timeouts to prevent slowloris ─────────────────────────
client_body_timeout   10;
client_header_timeout 10;
keepalive_timeout     5 5;
send_timeout          10;

# ── Block suspicious user-agents ──────────────────────────
map $http_user_agent $bad_bot {
    default         0;
    ~*malicious     1;
    ~*nikto         1;
    ~*sqlmap        1;
    ~*dirbuster     1;
    ~*masscan       1;
    ~*nmap          1;
    ~*w3af          1;
    ~*acunetix      1;
    ""              1;  # Block empty user-agents
}
EOF

# ── Default server block to drop unknown vhosts ───────────
cat > /etc/nginx/sites-available/default <<'EOF'
# Drop requests to unknown hosts
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # Apply rate limiting
    limit_req zone=general burst=20 nodelay;

    # Block bad bots
    if ($bad_bot) { return 444; }

    # Block common attack paths
    location ~* (\.php$|\.asp$|\.aspx$|\.cgi$|\.sh$|wp-admin|phpmyadmin|\.env$|\.git/) {
        return 444;
    }

    # Block SQL injection patterns in URI
    location ~* "(union|select|insert|drop|delete|update|cast|char|exec|declare|xp_cmdshell)" {
        return 444;
    }

    return 444;
}
EOF

# ── SSL/TLS template (fill in your domain) ────────────────
cat > /etc/nginx/snippets/ssl-security.conf <<'EOF'
# Paste into your HTTPS server block after running certbot
ssl_protocols               TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers   on;
ssl_ciphers                 ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256;
ssl_session_cache           shared:SSL:10m;
ssl_session_timeout         1d;
ssl_session_tickets         off;
ssl_stapling                on;
ssl_stapling_verify         on;
resolver                    1.1.1.1 8.8.8.8 valid=300s;
resolver_timeout            5s;
EOF

# ── Certbot for free SSL ───────────────────────────────────
if ! command -v certbot &>/dev/null; then
  apt-get install -y certbot python3-certbot-nginx
  echo "[09] Certbot installed — run: certbot --nginx -d yourdomain.com"
fi

# Test and reload Nginx
nginx -t && systemctl reload nginx

echo "[09] ✓ Nginx security headers, rate limiting, bad-bot blocking configured"
echo "[09]   Next: certbot --nginx -d YOUR_DOMAIN to enable HTTPS"
