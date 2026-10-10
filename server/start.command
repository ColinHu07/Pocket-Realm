#!/bin/zsh
# Double-click on macOS. The key stays in this process's environment, not a file.
set -eu
unsetopt xtrace verbose
cd -- "${0:A:h}"

if [[ -z "${GEMINI_API_KEY:-}" ]]; then
    read -rs 'GEMINI_API_KEY?Gemini API key (hidden while typing): ' || exit 1
    print
fi
if [[ -z "$GEMINI_API_KEY" ]]; then
    print 'No key entered. Run this launcher again to start the server.'
    exit 1
fi
export GEMINI_API_KEY
export GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.6-flash}"

realm_hostname=$(/usr/sbin/scutil --get LocalHostName)
print "Model: $GEMINI_MODEL"
print "Phone connection address: http://${realm_hostname}.local:${PORT:-8787}"
print 'Keep this window open while playing. Control-C stops the server.'
exec python3 server.py
