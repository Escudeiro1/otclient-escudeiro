#!/usr/bin/env bash
# Builds otclient + otclient-launcher via the repo's Dockerfile (for wider
# glibc/CPU compatibility -- see Dockerfile's `-march=x86-64-v2` on a
# gcc:13-bookworm base), assembles a self-contained dist/linux/ bundle from
# the build output plus the plain (non-compiled) files the client needs, and
# publishes it to the live site for the launcher's manifest endpoint to serve.
#
# Uses a DEDICATED buildx builder ("otclient-builder", created once via
# `docker buildx create --name otclient-builder --driver docker-container`)
# so this project's build cache is entirely separate from the default
# builder / anything else on this host -- any cleanup here is scoped to
# --builder otclient-builder specifically, never a bare `docker prune`.
# Output goes straight to files (buildx --output=local) via a scratch-based
# export-only Dockerfile stage, so no "otclient" image is ever loaded/tagged
# in the shared daemon's image store, and build cache is kept on
# /var/www/internalSSD (--cache-to/--cache-from), not the root filesystem.
#
# Usage: tools/publish-launcher-release.sh [--no-deploy]
#   --no-deploy   Stop after assembling dist/linux/; skip the rsync to
#                 /var/www/html/client-releases/current/linux/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DEPLOY=1
if [[ "${1:-}" == "--no-deploy" ]]; then
    DEPLOY=0
fi

WEBSITE_RELEASE_DIR="/var/www/html/client-releases/current/linux"
DIST_DIR="$REPO_ROOT/dist/linux"
CACHE_DIR="$REPO_ROOT/.buildx-cache"
BUILDER="otclient-builder"

if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
    echo "Dedicated builder '$BUILDER' not found. Create it once with:" >&2
    echo "  docker buildx create --name $BUILDER --driver docker-container" >&2
    exit 1
fi

mkdir -p "$DIST_DIR" "$CACHE_DIR"

echo "==> Building + exporting binaries via isolated builder '$BUILDER'"
docker buildx build \
    --builder "$BUILDER" \
    --target launcher-dist-export \
    --output "type=local,dest=$DIST_DIR" \
    --cache-to "type=local,dest=$CACHE_DIR,mode=max" \
    --cache-from "type=local,src=$CACHE_DIR" \
    .
chmod +x "$DIST_DIR/otclient" "$DIST_DIR/otclient-launcher"

echo "==> Copying plain (non-compiled) files from the working tree"
rm -rf "$DIST_DIR/modules" "$DIST_DIR/mods"
cp -a "$REPO_ROOT/modules" "$DIST_DIR/modules"
cp -a "$REPO_ROOT/mods" "$DIST_DIR/mods"
cp -a "$REPO_ROOT/init.lua" "$DIST_DIR/init.lua"
cp -a "$REPO_ROOT/cacert.pem" "$DIST_DIR/cacert.pem"

echo "==> Computing checksums and writing manifest.json"
python3 - "$DIST_DIR" <<'PYEOF'
import hashlib
import json
import os
import sys

dist_dir = sys.argv[1]

def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

files = {}
for tracked_dir in ("modules", "mods"):
    base = os.path.join(dist_dir, tracked_dir)
    for root, _dirs, filenames in os.walk(base):
        for name in filenames:
            full = os.path.join(root, name)
            rel = os.path.relpath(full, dist_dir).replace(os.sep, "/")
            files[rel] = sha256_of(full)

for rel in ("init.lua", "cacert.pem"):
    files[rel] = sha256_of(os.path.join(dist_dir, rel))

manifest = {
    "files": files,
    "client": {"file": "otclient", "checksum": sha256_of(os.path.join(dist_dir, "otclient"))},
    "launcher": {"file": "otclient-launcher", "checksum": sha256_of(os.path.join(dist_dir, "otclient-launcher"))},
    "keepFiles": False,
}

with open(os.path.join(dist_dir, "manifest.json"), "w") as f:
    json.dump(manifest, f)

print(f"  {len(files)} tracked files hashed")
PYEOF

echo "==> dist/linux/ ready at $DIST_DIR"

if [[ "$DEPLOY" -eq 1 ]]; then
    echo "==> Publishing to $WEBSITE_RELEASE_DIR"
    mkdir -p "$WEBSITE_RELEASE_DIR"
    rsync -a --delete "$DIST_DIR/" "$WEBSITE_RELEASE_DIR/"
    echo "==> Published."
else
    echo "==> --no-deploy set; skipped publishing to $WEBSITE_RELEASE_DIR"
fi

# Scoped to ONLY this project's dedicated builder -- never a bare `docker
# prune`/`docker system prune`, which would affect every other image and
# container on this host. This keeps the builder's own transient state from
# accumulating across repeated runs; the real cache lives externally at
# $CACHE_DIR (on internalSSD) via --cache-to/--cache-from above, so nothing
# is lost by pruning the builder's internal state here.
echo "==> Pruning otclient-builder's own build cache (scoped to this builder only)"
docker buildx prune --builder "$BUILDER" -f >/dev/null
echo "==> Done."
