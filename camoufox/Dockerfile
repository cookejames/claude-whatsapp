# Camoufox (anti-detect Firefox) on a web desktop, driven by Claude through
# Playwright MCP served over HTTP on the private compose network.
#   https://localhost:3002  the desktop, to watch, log in or pass a challenge
#   http://camoufox:8931/mcp  Playwright MCP, for the claude container only
FROM lscr.io/linuxserver/baseimage-selkies:debiantrixie

ARG CAMOUFOX_VERSION=0.5.6
ARG PLAYWRIGHT_MCP_VERSION=0.0.82

ENV TITLE=Browser \
    CAMOUFOX_HOME=/opt/camoufox-home

# The base image already carries the NodeSource apt repository.
RUN apt-get update && apt-get install -y --no-install-recommends \
        nodejs python3-venv \
        libgtk-3-0t64 libdbus-glib-1-2 libasound2t64 libx11-xcb1 libxtst6 \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/camoufox \
    && /opt/camoufox/bin/pip install -q "camoufox==${CAMOUFOX_VERSION}" \
    && HOME=$CAMOUFOX_HOME /opt/camoufox/bin/python -m camoufox fetch \
    && chmod -R a+rwX $CAMOUFOX_HOME

RUN npm install -g --no-fund --no-audit "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}"

COPY --chmod=755 root/usr/local/bin/ /usr/local/bin/
COPY root/defaults/autostart /defaults/autostart
