#!/usr/bin/env bash
# One-time setup: grants the escudeiro user write access to the two paths
# under /var/www/html that the launcher-manifest endpoint needs, without
# loosening permissions on the web root itself. Run once with sudo:
#
#   sudo tools/setup-launcher-manifest-hosting.sh
#
# After this, launcher-manifest.php can be created/edited and
# tools/publish-launcher-release.sh can rsync into client-releases/
# without needing sudo again.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run this with sudo." >&2
    exit 1
fi

WEB_USER="escudeiro"
WEB_GROUP="nginx"

mkdir -p /var/www/html/client-releases
chown "$WEB_USER:$WEB_GROUP" /var/www/html/client-releases

touch /var/www/html/launcher-manifest.php
chown "$WEB_USER:$WEB_GROUP" /var/www/html/launcher-manifest.php

echo "Done. /var/www/html/client-releases and /var/www/html/launcher-manifest.php are now owned by $WEB_USER:$WEB_GROUP."
