# Herdr Agent Runtime — Secure Docker Container

> A hardened Docker container for running **Herdr** (agent runtime) + **Moshi** (mobile bridge) on your VPS, designed for multi-agent orchestration with full security isolation.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Your VPS (Production websites, other services...)       │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  herdr-agent-runtime (Docker Container)             │ │
│  │  ┌───────────────────┐  ┌────────────────────────┐  │ │
│  │  │   SSH Server       │  │  Herdr Server          │  │ │
│  │  │   (port 22→2222)   │  │  (agent runtime)       │  │ │
│  │  └───────────────────┘  └────────────────────────┘  │ │
│  │  ┌───────────────────┐  ┌────────────────────────┐  │ │
│  │  │  moshi-hook        │  │  ~/projects/           │  │ │
│  │  │  (mobile bridge)   │  │  (persistent volume)   │  │ │
│  │  └───────────────────┘  └────────────────────────┘  │ │
│  │                                                     │ │
│  │  User: developer (UID 1000, passwordless sudo)      │ │
│  │  Limits: 2 CPU cores, 6 GB RAM                      │ │
│  │  No docker.sock, no host access                     │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### 1. Clone and configure

```bash
cd herdr-agent
cp .env.example .env
nano .env  # Set your password and SSH keys
```

### 2. Build and run

```bash
docker compose up -d --build
```

### 3. SSH into the container

```bash
ssh developer@your-vps-ip -p 2222
```

### 4. Start using Herdr

```bash
# Inside the container:
herdr                        # Launch Herdr
herdr workspace new myapp    # Create a workspace
herdr agent start            # Start an agent
```

## 🔐 Security Features

| Feature | Status |
|---------|--------|
| Non-root user (`developer`) | ✅ |
| Passwordless sudo (for installs) | ✅ |
| No docker.sock access | ✅ |
| No host PID namespace | ✅ |
| All capabilities dropped + only needed ones added | ✅ |
| Isolated bridge network | ✅ |
| SSH root login disabled | ✅ |
| Resource limits enforced (2 CPU, 6 GB RAM) | ✅ |
| tmpfs for /tmp and /run | ✅ |
| Log rotation (10 MB × 3) | ✅ |

## 📋 What's Installed

| Tool | Purpose |
|------|---------|
| **Herdr** | Agent runtime — terminal multiplexer, workspace manager, agent orchestration CLI/socket API |
| **moshi-hook** | Mobile bridge — remote agent approvals and status from your phone via Moshi app |
| **tmux** | Fallback terminal multiplexer |
| **Node.js 22** | JavaScript runtime (many agents need it) |
| **Python 3** | Python runtime + pip + venv |
| **build-essential** | gcc, make, etc. for compiling dependencies |
| **Git** | Version control |
| **SSH server** | Remote access into the container |

## 🔧 Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DEVELOPER_PASSWORD` | `agent2024` | SSH password for developer user |
| `SSH_AUTHORIZED_KEYS` | _(empty)_ | SSH public key(s) for key-based auth |
| `MOSHI_HOOK_TOKEN` | _(empty)_ | Moshi pairing token from Settings → Hooks |
| `TZ` | `UTC` | Container timezone |

### Windows: Passwordless SSH Setup (Recommended)

1. Open PowerShell on your Windows machine and generate a dedicated SSH key (press **Enter twice** to skip the passphrase):
   ```powershell
   ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\herdr_key"
   ```
2. Print your new public key and copy the output:
   ```powershell
   Get-Content "$env:USERPROFILE\.ssh\herdr_key.pub"
   ```
3. Add the copied key to the `SSH_AUTHORIZED_KEYS` environment variable in Dokploy (or your `.env` file).
4. Open your SSH config file (`C:\Users\<your-username>\.ssh\config`) and add this block:
   ```text
   Host herdr
       HostName <YOUR_VPS_IP>
       Port 2224
       User developer
       IdentityFile ~/.ssh/herdr_key
   ```

### Windows: Instant Terminal Drop-in (`herdragent.cmd`)

To create a global command that drops you instantly into the Herdr interface without typing SSH commands:

1. In a directory that is in your Windows PATH (e.g., `C:\Users\<your-username>\Scripts`), create a file named `herdragent.cmd`.
2. Add the following content:
   ```cmd
   @echo off
   ssh -t herdr "herdr"
   ```
3. Now, you can open any Windows terminal and simply type `herdragent` to securely launch your workspace in one keystroke!

### Moshi Mobile Setup

```bash
# Inside the container:
moshi-hook pair --token <token-from-moshi-app>
moshi-hook install
moshi-hook serve &
```

## 🐏 Herdr Multi-Agent Orchestration

Once inside the container, Herdr gives you full agent orchestration:

```bash
# Create workspaces for different projects
herdr workspace new project-alpha
herdr workspace new project-beta

# Start agents in workspaces
herdr agent start reviewer --kind codex
herdr agent prompt reviewer "Review the current diff" --wait

# Agents can communicate with each other
herdr agent wait reviewer --until blocked
herdr agent read reviewer --source recent-unwrapped

# Split panes, manage terminals
herdr pane split --current --direction right --no-focus

# Check agent states across all workspaces
herdr          # Opens the TUI showing all workspaces + agents
```

## 📁 File Structure

```
herdr-agent/
├── Dockerfile           # Multi-stage build, Ubuntu 24.04 base
├── docker-compose.yml   # Compose with resource limits + security
├── entrypoint.sh        # Init script (SSH + Herdr + moshi-hook)
├── .env.example         # Environment template
├── .dockerignore        # Exclude secrets from build context
└── README.md            # This file
```

## 🔄 Dokploy Deployment

This setup is fully compatible with **Dokploy**:

1. Push the repository to your Git provider
2. In Dokploy, create a new **Compose** project
3. Point it to your repo containing the `docker-compose.yml`
4. Set environment variables in Dokploy's UI
5. Deploy!

> **Note:** Dokploy uses `docker compose` under the hood, so all resource limits, security settings, and volumes work as configured.

## ⚠️ Important Notes

- **Change the default password** before deploying to production
- **Use SSH keys** instead of password auth for better security
- The container **cannot** access or control other Docker containers
- Agents running inside are sandboxed to the container's filesystem
- The persistent volume (`herdr-home`) survives container restarts
- Resource limits (2 CPU, 6 GB RAM) are **hard caps** — processes will be killed if they exceed RAM
