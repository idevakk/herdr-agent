#!/bin/bash
# =============================================================================
# Entrypoint for Herdr Agent Runtime Container
# =============================================================================
# Starts SSH server, sets up Herdr server, and launches moshi-hook daemon.
# Runs as root initially, then services drop to developer user.
# =============================================================================

set -e

echo "══════════════════════════════════════════════════════════════"
echo "  🐏 Herdr Agent Runtime Container"
echo "══════════════════════════════════════════════════════════════"

# ── Generate SSH host keys if missing ────────────────────────────────────────
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "[init] Generating SSH host keys..."
    ssh-keygen -A
fi

# ── Set developer password from env if provided ─────────────────────────────
if [ -n "$DEVELOPER_PASSWORD" ]; then
    echo "[init] Setting developer password from environment..."
    echo "developer:${DEVELOPER_PASSWORD}" | chpasswd
fi

# ── Import SSH authorized keys from env if provided ──────────────────────────
if [ -n "$SSH_AUTHORIZED_KEYS" ]; then
    echo "[init] Importing SSH authorized keys..."
    echo "$SSH_AUTHORIZED_KEYS" > /home/developer/.ssh/authorized_keys
    chmod 600 /home/developer/.ssh/authorized_keys
    chown developer:developer /home/developer/.ssh/authorized_keys
fi

# ── Import authorized keys from mounted volume ──────────────────────────────
if [ -f /home/developer/.ssh/authorized_keys ]; then
    chmod 600 /home/developer/.ssh/authorized_keys
    chown developer:developer /home/developer/.ssh/authorized_keys
fi

# ── Start SSH server ────────────────────────────────────────────────────────
echo "[init] Starting SSH server..."
/usr/sbin/sshd

# ── Start Herdr server as developer user (background) ───────────────────────
echo "[init] Starting Herdr server..."
su - developer -c "herdr server start" 2>/dev/null || \
    echo "[init] Herdr server start skipped (may need first-run setup)"

# ── Start moshi-hook daemon as developer user (background) ──────────────────
if [ -n "$MOSHI_HOOK_TOKEN" ]; then
    echo "[init] Pairing moshi-hook..."
    su - developer -c "moshi-hook pair --token ${MOSHI_HOOK_TOKEN}" 2>/dev/null || true
fi

echo "[init] Starting moshi-hook daemon..."
su - developer -c "nohup moshi-hook serve > /dev/null 2>&1 &" 2>/dev/null || \
    echo "[init] moshi-hook start skipped (pair first via: moshi-hook pair --token <token>)"

# ── Print access info ───────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ✅ Container ready!"
echo ""
echo "  SSH Access:"
echo "    ssh developer@<host-ip> -p <mapped-port>"
echo "    Default password: agent2024 (change via DEVELOPER_PASSWORD env)"
echo ""
echo "  Inside the container:"
echo "    herdr                    # Start/attach to Herdr"
echo "    herdr workspace new foo  # Create a workspace"
echo "    herdr agent start        # Start an agent in current workspace"
echo "    moshi-hook status        # Check Moshi hook status"
echo ""
echo "  Resource limits:"
echo "    CPU: 2 cores  |  RAM: 6 GB"
echo "══════════════════════════════════════════════════════════════"
echo ""

# ── Keep the container alive ────────────────────────────────────────────────
# We tail /dev/null to keep the container running. SSH and Herdr server
# are already running in the background.
exec tail -f /dev/null
