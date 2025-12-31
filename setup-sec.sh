#!/bin/bash
set -e

### ========= VARIABLES =========
DOMAIN="hacxs.me"
N8N_USER="admin"
INSTALL_DIR="/opt/n8n"
TIMEZONE="Asia/Kolkata"
RESTART_HOUR="3"
### =============================

echo "[+] Updating system"
sudo apt update && sudo apt upgrade -y

echo "[+] Installing Docker"
sudo apt install -y ca-certificates curl gnupg
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo systemctl enable docker
sudo systemctl start docker

echo "[+] Allow docker without sudo"
sudo usermod -aG docker $USER

echo "[+] Installing Docker Compose plugin"
mkdir -p ~/.docker/cli-plugins/
if [ ! -f ~/.docker/cli-plugins/docker-compose ]; then
  curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
    -o ~/.docker/cli-plugins/docker-compose
  chmod +x ~/.docker/cli-plugins/docker-compose
fi

echo "[+] Creating n8n directory"
sudo mkdir -p $INSTALL_DIR
sudo chown -R $USER:$USER $INSTALL_DIR
cd $INSTALL_DIR

if [ -f .env ]; then
  N8N_PASSWORD=$(grep N8N_BASIC_AUTH_PASSWORD .env | cut -d= -f2)
  echo "[+] Existing password preserved"
else
  N8N_PASSWORD=$(openssl rand -base64 32)
  echo "[+] Generated password: $N8N_PASSWORD"
fi

cat > .env <<EOF
DOMAIN_NAME=${DOMAIN}

N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=${N8N_USER}
N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}

N8N_HOST=${DOMAIN}
N8N_PORT=5678
N8N_PROTOCOL=https
WEBHOOK_URL=https://${DOMAIN}/

TZ=${TIMEZONE}
EXECUTIONS_MODE=regular
EOF

cat > Caddyfile <<EOF
${DOMAIN} {
  header {
    X-Content-Type-Options nosniff
    X-Frame-Options DENY
    X-XSS-Protection "1; mode=block"
    Referrer-Policy strict-origin
    Permissions-Policy "geolocation=(), microphone=(), camera=()"
  }
  reverse_proxy n8n:5678
}
EOF

cat > docker-compose.yml <<EOF
version: "3.8"

services:
  n8n:
    image: n8nio/n8n:latest
    restart: always
    env_file:
      - .env
    volumes:
      - n8n_data:/home/node/.n8n

    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

    mem_limit: 1g

  caddy:
    image: caddy:latest
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config

volumes:
  n8n_data:
  caddy_data:
  caddy_config:
EOF

sudo ufw allow OpenSSH
sudo ufw allow 80
sudo ufw allow 443
sudo ufw --force enable

docker compose up -d

cat > restart-n8n.sh <<EOF
#!/bin/bash
docker restart n8n-n8n-1
EOF
chmod +x restart-n8n.sh

(crontab -l 2>/dev/null; echo "0 ${RESTART_HOUR} * * * ${INSTALL_DIR}/restart-n8n.sh >> /var/log/n8n-restart.log 2>&1") | crontab -

echo "=========================================="
echo "✅ n8n deployed successfully!"
echo "🌐 URL: https://${DOMAIN}"
echo "👤 User: ${N8N_USER}"
echo "🔐 Password: ${N8N_PASSWORD}"
echo "⏰ Daily restart: ${RESTART_HOUR}:00"
echo "=========================================="
