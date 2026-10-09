# Claude Code + WhatsApp channel, running an interactive session inside tmux.
# Build context is the repo root; the private package list comes from the
# `local` additional context (../local/config) declared in docker-compose.yml.
FROM debian:bookworm-slim

ARG TARGETARCH
ARG USERNAME=claude
ARG USER_UID=1000
ARG USER_GID=1000
ARG NODE_MAJOR=22
ARG YQ_VERSION=v4.44.3

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color

# --- Base OS ---------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash build-essential ca-certificates curl file git gnupg jq less \
        locales procps sudo tini tmux tzdata unzip vim-tiny xz-utils \
    && curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${TARGETARCH}" \
        -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq \
    && curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# --- Non-root user (Claude refuses --dangerously-skip-permissions as root) --
RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /bin/bash "${USERNAME}" \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}" \
    && chmod 0440 "/etc/sudoers.d/${USERNAME}" \
    && mkdir -p /home/linuxbrew /config /workspace /opt/defaults \
    && chown -R "${USERNAME}:${USERNAME}" /home/linuxbrew /config /workspace

USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew \
    HOMEBREW_NO_ANALYTICS=1 \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    CLAUDE_CONFIG_DIR=/home/${USERNAME}/.claude \
    BUN_INSTALL=/home/${USERNAME}/.bun \
    NPM_CONFIG_PREFIX=/home/${USERNAME}/.npm-global
ENV PATH=/home/${USERNAME}/.local/bin:/home/${USERNAME}/.bun/bin:/home/${USERNAME}/.npm-global/bin:${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:${PATH}
# Login shells reset PATH from /etc/profile; restore the tool paths there too.
RUN echo "export PATH=\"${PATH}\"" | sudo tee /etc/profile.d/10-tools.sh >/dev/null

# --- Homebrew, Bun, uv, Claude Code ----------------------------------------
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    && brew --version
RUN curl -fsSL https://bun.sh/install | bash && bun --version
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && uv --version
RUN curl -fsSL https://claude.ai/install.sh | bash && claude --version

# --- Voice transcription: faster-whisper for whisper-transcribe.sh ----------
ARG FASTER_WHISPER_VERSION=1.2.1
RUN sudo install -d -o "${USERNAME}" -g "${USERNAME}" /opt/whisper \
    && uv venv --no-cache -q /opt/whisper \
    && uv pip install --no-cache -q --python /opt/whisper/bin/python "faster-whisper==${FASTER_WHISPER_VERSION}"

# --- Declared packages (defaults + private local list) ---------------------
COPY --chmod=755 claude/scripts/ /usr/local/bin/
# The WhatsApp plugin looks for its transcription script at this fixed path.
RUN ln -s /usr/local/bin/whisper-transcribe.sh "/home/${USERNAME}/whisper-transcribe.sh"
COPY defaults/ /opt/defaults/
COPY --from=local install.yaml /tmp/install.local.yaml
RUN /usr/local/bin/build-install.sh /opt/defaults/install.yaml /tmp/install.local.yaml

WORKDIR /workspace
HEALTHCHECK --interval=60s --timeout=10s --start-period=120s \
    CMD tmux has-session -t claude 2>/dev/null && pgrep -x claude >/dev/null || exit 1
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
