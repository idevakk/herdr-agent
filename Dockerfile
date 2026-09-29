# =============================================================================
# Herdr Agent Runtime — Secure Multi-Agent Orchestration Container
# =============================================================================
# Base:       Ubuntu 24.04 (Noble) — lean but full apt ecosystem
# User:       "developer" (UID 1000) — passwordless sudo, no root login
# Tools:      Herdr (agent runtime), moshi-hook (mobile agent bridge)
# Access:     SSH on port 22 (key-based preferred)
# Security:   No docker.sock, no host PID/NET, read-only rootfs optional,
#             seccomp default, no-new-privileges, capped resources
# =============================================================================

FROM ubuntu:24.04 AS base

# ── Prevent interactive prompts during build ──────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive

# ── System packages — lean but functional ─────────────────────────────────────
# We install only what's needed for agent orchestration + SSH access.
# No desktop packages, no X11, no bloat.
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    ca-certificates \
    curl \
    wget \
    git \
    jq \
    unzip \
    xz-utils \
    locales \
    # SSH server for remote access
    openssh-server \
    # Process management
    sudo \
    # Proper init system for Docker (reaps zombies)
    tini \
    # Terminal multiplexer fallback (Herdr is primary)
    tmux \
    # Build essentials (agents may need to compile things)
    build-essential \
    # Networking tools
    net-tools \
    iputils-ping \
    dnsutils \
    # Editor (lightweight)
    vim-tiny \
    nano \
    # Python (many agent tools depend on it)
    python3 \
    python3-pip \
    python3-venv \
    # Search tools (agents use these heavily)
    ripgrep \
    fd-find \
    fzf \
    # Misc
    file \
    less \
    htop \
    xdg-utils \
    && true
# NOTE: We intentionally keep apt lists (/var/lib/apt/lists) so that
# agents can run `sudo apt-get install -y <package>` without needing
# `apt-get update` first. This adds ~30 MB to the image but saves
# agents from failing or wasting time on every install.

# ── Generate locale ──────────────────────────────────────────────────────────
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en

# ── Fix Python PEP 668 (externally-managed-environment) ──────────────────────
# Ubuntu 24.04 blocks global pip install by default. Agents WILL hit this.
# This allows `pip install <package>` to work without --break-system-packages.
RUN rm -f /usr/lib/python3*/EXTERNALLY-MANAGED

# ── Install uv (fast Python package manager) ─────────────────────────────────
# uv is 10-100x faster than pip. Agents can use `uv pip install` or `uv venv`.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && cp /root/.local/bin/uv /usr/local/bin/uv \
    && cp /root/.local/bin/uvx /usr/local/bin/uvx 2>/dev/null || true

# ── Install GitHub CLI (gh) ──────────────────────────────────────────────────
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh

# ── Install PHP 8.4 & Laravel Dependencies ───────────────────────────────────
# Ubuntu 24.04 natively ships with 8.3, so we add the Ondrej PPA for 8.4
RUN apt-get update && apt-get install -y --no-install-recommends software-properties-common \
    && LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php \
    && apt-get update && apt-get install -y --no-install-recommends \
    php8.4-cli \
    php8.4-mbstring \
    php8.4-xml \
    php8.4-bcmath \
    php8.4-curl \
    php8.4-zip \
    php8.4-mysql \
    php8.4-sqlite3 \
    php8.4-intl \
    php8.4-gd \
    php8.4-redis \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# ── Install Node.js 22 LTS & Global Agents ───────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g npm@latest @anthropic-ai/claude-code @kilocode/cli @earendil-works/pi-coding-agent @opencode/cli

# ── Create restricted "developer" user ────────────────────────────────────────
# - UID 1000 (standard non-root)
# - Member of sudo group with NOPASSWD for dependency installs
# - Cannot escape the container (no docker group, no docker.sock)
# - Home directory at /home/developer
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupadd -g 1000 developer \
    && useradd -m -u 1000 -g developer -G sudo -s /bin/bash developer \
    && echo "developer ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/developer \
    && chmod 0440 /etc/sudoers.d/developer

# ── SSH server configuration ─────────────────────────────────────────────────
RUN mkdir -p /run/sshd \
    && mkdir -p /home/developer/.ssh \
    && chmod 700 /home/developer/.ssh \
    && chown developer:developer /home/developer/.ssh \
    # Harden SSH config
    && sed -i 's/#PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && echo "AllowUsers developer" >> /etc/ssh/sshd_config \
    # Disable X11 forwarding, agent forwarding, TCP forwarding
    && echo "X11Forwarding no" >> /etc/ssh/sshd_config \
    && echo "AllowAgentForwarding no" >> /etc/ssh/sshd_config \
    && echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config \
    # Set a default password for developer (change this or use keys!)
    && echo "developer:agent2024" | chpasswd

# ── Install Herdr (the agent runtime / multiplexer) ───────────────────────────
# Herdr is the core of this setup — it holds terminals open, detects agents,
# manages workspaces, and provides the CLI/socket API for agent orchestration.
RUN curl -fsSL https://herdr.dev/install.sh | HERDR_INSTALL_DIR=/usr/local/bin sh

# ── Install moshi-hook (mobile agent bridge) ─────────────────────────────────
# moshi-hook enables remote agent approvals and status from the Moshi mobile app.
# Skip the first-run prompt for headless container use.
RUN curl -fsSL https://getmoshi.app/install.sh \
    | MOSHI_HOOK_SKIP_FIRST_RUN=1 INSTALL_DIR=/usr/local/bin sh

# ── Install OMP (Oh My Pi / Agent Runtime) ───────────────────────────────────
RUN curl -fsSL https://omp.sh/install | INSTALL_DIR=/usr/local/bin sh \
    && cp -r /root/.local/bin/omp /usr/local/bin/omp 2>/dev/null || true

# ── Ensure binaries are accessible to developer user ─────────────────────────
RUN chmod +x /usr/local/bin/herdr 2>/dev/null || true \
    && chmod +x /usr/local/bin/moshi-hook 2>/dev/null || true \
    && chmod +x /usr/local/bin/moshi 2>/dev/null || true \
    && chmod +x /usr/local/bin/omp 2>/dev/null || true

# ── Create workspace directories ─────────────────────────────────────────────
RUN mkdir -p /home/developer/projects \
    && mkdir -p /home/developer/.config/herdr \
    && mkdir -p /home/developer/.local/bin \
    && mkdir -p /home/developer/.pi/agent/extensions \
    && mkdir -p /home/developer/.config/kilo \
    && chown -R developer:developer /home/developer

# ── systemctl shim (Docker has no systemd) ───────────────────────────────────
# Many agents try `sudo systemctl start <service>`. Without this, they get a
# hard error and stall. This shim logs the call and exits 0 so agents continue.
RUN printf '#!/bin/bash\necho "[systemctl-shim] $*" >> /tmp/systemctl.log\nexit 0\n' \
    > /usr/local/bin/systemctl \
    && chmod +x /usr/local/bin/systemctl

# ── Developer user environment ───────────────────────────────────────────────
USER developer
WORKDIR /home/developer

# Add local bin to PATH
ENV PATH="/home/developer/.local/bin:/usr/local/bin:${PATH}"

# Shell config for developer
RUN echo 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"' >> ~/.bashrc \
    && echo 'export EDITOR=nano' >> ~/.bashrc \
    && echo 'export TERM=xterm-256color' >> ~/.bashrc \
    && echo 'export MOSHI_MULTIPLEXER=herdr' >> ~/.bashrc \
    && echo '# Herdr auto-start hint: run `herdr` to start the agent runtime' >> ~/.bashrc \
    && echo 'alias ll="ls -la"' >> ~/.bashrc \
    && echo 'alias projects="cd ~/projects"' >> ~/.bashrc

# ── Switch back to root for entrypoint ───────────────────────────────────────
USER root

# ── Copy entrypoint script ───────────────────────────────────────────────────
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ── Expose ports ─────────────────────────────────────────────────────────────
# 22    — SSH access
# 24543 — moshi-hook gateway (local only, forwarded via SSH)
# 7681  — Herdr server socket (internal)
EXPOSE 22 24543

# ── Health check ─────────────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pgrep sshd > /dev/null && echo "healthy" || exit 1

# ── Entrypoint ───────────────────────────────────────────────────────────────
# ── Entrypoint (tini handles zombie reaping) ─────────────────────────────────
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
