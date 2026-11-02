#!/bin/bash
# Run on a disposable Amazon Linux 2023 x86_64 builder after placing application/ in /tmp/veriqta-application.
set -euo pipefail
dnf install -y python3 python3-pip amazon-cloudwatch-agent
useradd --system --home-dir /opt/veriqta --shell /sbin/nologin veriqta || id veriqta
install -d -m 755 /opt/veriqta /var/log/veriqta
python3 -m venv /opt/veriqta/venv
/opt/veriqta/venv/bin/pip install -r /tmp/veriqta-application/requirements.txt
install -m 644 /tmp/veriqta-application/app.py /opt/veriqta/app.py
curl --fail --location --proto '=https' --tlsv1.2 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /opt/veriqta/rds-ca.pem
chown veriqta:veriqta /var/log/veriqta
cat > /etc/systemd/system/veriqta-api.service <<'UNIT'
[Unit]
Description=Veriqta portfolio API
After=network-online.target
Wants=network-online.target
[Service]
User=veriqta
Group=veriqta
EnvironmentFile=/etc/veriqta.env
ExecStart=/opt/veriqta/venv/bin/python /opt/veriqta/app.py
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/log/veriqta
StandardOutput=append:/var/log/veriqta/app.log
StandardError=append:/var/log/veriqta/app.log
[Install]
WantedBy=multi-user.target
UNIT
# Enable at launch, after user data creates the environment file.
systemctl disable veriqta-api || true
rm -f /etc/veriqta.env
