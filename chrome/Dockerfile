# linuxserver/chrome (Chrome on a desktop you view in the browser) with:
#  - a managed policy that force-installs and pins the Claude extension
#  - a wrapper that can give Chrome a macOS user agent
# Claude drives it through that extension once you sign it in to claude.ai.
FROM lscr.io/linuxserver/chrome:latest
RUN mv /usr/bin/wrapped-chrome /usr/bin/wrapped-chrome.orig
COPY --chmod=755 root/usr/bin/wrapped-chrome /usr/bin/wrapped-chrome
COPY root/etc/opt/chrome/ /etc/opt/chrome/
RUN chmod -R a+rX /etc/opt/chrome
