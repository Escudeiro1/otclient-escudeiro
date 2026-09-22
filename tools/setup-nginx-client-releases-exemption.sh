#!/usr/bin/env bash
# One-time nginx config change: exempts /client-releases/ from the site's
# blanket .json/.log/.sql/etc deny-all rule (nginx.conf, the
# `location ~* \.(?:md|json|dist|sql|bak|old|backup|tpl|twig|log)$` block).
# That rule exists to stop leaking things like composer.json or .sql dumps
# that might accidentally sit in the web root -- but /client-releases/ only
# ever contains files tools/publish-launcher-release.sh put there, all
# meant to be publicly downloadable by design. The dotfile-deny rule
# (.git/.env/etc) is deliberately re-applied inside the exemption so that
# protection stays active for this directory too -- only the specific
# extension rule is bypassed, nothing else.
#
# Run once with sudo:
#   sudo tools/setup-nginx-client-releases-exemption.sh
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run this with sudo." >&2
    exit 1
fi

NGINX_CONF="/etc/nginx/nginx.conf"
MARKER="location ^~ /client-releases/"

if grep -qF "$MARKER" "$NGINX_CONF"; then
    echo "Already applied ($MARKER found in $NGINX_CONF). Nothing to do."
    exit 0
fi

BACKUP="$NGINX_CONF.bak.$(date +%s)"
cp "$NGINX_CONF" "$BACKUP"
echo "Backed up $NGINX_CONF -> $BACKUP"

python3 - "$NGINX_CONF" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

anchor = "    location ~* /\\.(?:ht|git|svn|env)$ {"
if anchor not in content:
    print("ERROR: expected anchor line not found, aborting without changes.", file=sys.stderr)
    sys.exit(1)

block = (
    "    # client-releases/ only ever contains files tools/publish-launcher-release.sh\n"
    "    # placed there -- all meant to be publicly downloadable by design, unlike the\n"
    "    # rest of the site root. ^~ makes this prefix match take priority over the\n"
    "    # regex locations below, so the .json/.log/.sql/etc deny rule never applies\n"
    "    # here; the dotfile-deny rule is re-applied below so that protection stays\n"
    "    # active for this directory too.\n"
    "    location ^~ /client-releases/ {\n"
    "        location ~* /\\.(?:ht|git|svn|env)$ {\n"
    "            deny all;\n"
    "        }\n"
    "    }\n\n"
)

content = content.replace(anchor, block + anchor, 1)

with open(path, "w") as f:
    f.write(content)

print("Inserted client-releases/ exemption block.")
PYEOF

echo "Testing nginx config..."
if ! nginx -t; then
    echo "Config test FAILED -- restoring backup, nothing was reloaded." >&2
    cp "$BACKUP" "$NGINX_CONF"
    exit 1
fi

echo "Reloading nginx..."
systemctl reload nginx

echo "Done. /client-releases/ is now exempt from the .json/.log/.sql/etc deny rule (dotfile protection still active)."
