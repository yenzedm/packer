#!/bin/bash
sudo set -euo pipefail

echo "=== Cleaning the system from extra SSH services and configuring classic sshd ==="

# 1. Stop all conflicting SSH services
echo "→ Stopping all SSH services..."
sudo systemctl stop ssh.service 2>/dev/null || true
sudo systemctl stop ssh.socket 2>/dev/null || true
sudo systemctl stop snap.sshd.service 2>/dev/null || true

# 2. Disable socket activation and snap variants
echo "→ Disabling socket activation..."
sudo systemctl disable ssh.socket 2>/dev/null || true
sudo systemctl mask ssh.socket 2>/dev/null || true

echo "→ Removing snap sshd (if exists)..."
if snap list 2>/dev/null | grep -q ssh; then
  sudo snap remove ssh --purge || true
fi

# 3. Enable only classic systemd sshd
echo "→ Enabling ssh.service..."
sudo systemctl unmask ssh.service 2>/dev/null || true
sudo systemctl enable ssh.service
sudo systemctl daemon-reload

# 4. Check config presence and clean possible cloud-init overrides
echo "→ Checking /etc/ssh configuration..."
sudo mkdir -p /etc/ssh/sshd_config.d
sudo rm -f /etc/ssh/sshd_config.d/*cloud-init*.conf || true
sudo rm -f /run/sshd_config /run/sshd_config.d/* || true

# 5. Update systemd configuration — ensure restart applies immediately
echo "→ Setting up /etc/systemd/system/ssh.service override..."
sudo mkdir -p /etc/systemd/system/ssh.service.d
sudo cat > /etc/systemd/system/ssh.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/sbin/sshd -D $SSHD_OPTS
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload

# 6. Restart sshd
echo "→ Restarting sshd..."
sudo systemctl restart ssh.service

# 7. Verify the result
echo "=== Checking final state ==="
sudo systemctl is-active --quiet ssh.service && echo "✔ ssh.service is active"
sudo systemctl is-enabled --quiet ssh.service && echo "✔ ssh.service is enabled at boot"

echo "→ Checking for other SSH units:"
sudo systemctl list-units --type=service | grep ssh || echo "✔ Only ssh.service remains"
sudo systemctl list-unit-files | grep ssh

echo "→ Checking listening daemon:"
sudo ss -tlnp | grep sshd || echo "⚠ sshd is not listening yet (check the config)"

echo "→ Checking sshd configuration:"
sudo sshd -T | grep -E "port|passwordauthentication"

echo "=== Done: only the classic sshd.service remains ==="
