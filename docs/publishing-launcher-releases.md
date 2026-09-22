# Publishing launcher releases

How to build and ship a new client release through `otclient-launcher`, and
how the production server was set up to receive it. Read
[`docs/client-assets-auto-install.md`](client-assets-auto-install.md) for the
*separate* system that manages Tibia's own sprite/sound versioning inside
`data/things/`/`data/sounds/` — this doc is about the launcher's own update
mechanism (client code + binaries + those same asset directories, bundled).

## The regular workflow (every time you want to publish)

Run on the dev/build box, from the repo root:

```bash
tools/publish-launcher-release.sh --no-deploy
```

This builds `otclient` + `otclient-launcher` via Docker (the dedicated
`otclient-builder` buildx builder, isolated cache on this repo's own disk —
see the script's own comments for why), zips `modules/`, `mods/`, and `data/`
(the full directory, sprites/sounds included), copies the individually-synced
files (`init.lua`, `cacert.pem`) and the bootstrap-only `otclientrc.lua`, and
writes `dist/linux/manifest.json` describing all of it. Nothing is deployed
anywhere yet — `--no-deploy` stops right after `dist/linux/` is ready.

Then sync it to production yourself:

```bash
rsync -avz --no-owner --no-group \
    /var/www/internalSSD/escudeirot/otclient-escudeiro/dist/linux/ \
    escudeiro@45.234.93.69:/var/www/html/client-releases/current/linux/
```

(`--no-owner --no-group`: production's `client-releases/` directory has the
`setgid` bit set so new files automatically inherit the `www-data` group —
letting `rsync` try to *also* explicitly set owner/group itself just fails
with a permission error, since your SSH user isn't allowed to chgrp to groups
it doesn't fully control, even ones it's a member of.)

That's the whole release cycle. No version numbers to bump anywhere — the
manifest is just "what a correct install looks like right now" (SHA-256
checksums), and every running launcher detects the mismatch on its next
check and pulls whatever changed.

### What gets re-downloaded when you publish

- `init.lua`, `cacert.pem` — only if that specific file's content changed.
- `otclientrc.lua` — never touched once a player already has one (protects
  their customizations); only fetched on a fresh install where it's missing.
- `modules.zip` / `mods.zip` / `data.zip` — **whole-directory units.** Change
  *one* file inside `modules/` and the entire `modules/` directory gets
  wiped and re-extracted for every player, not just that file. Same for
  `data.zip` — bumping the Tibia asset version means everyone re-downloads
  the full archive (currently ~244MB, since it includes `data/things/` and
  `data/sounds/`), not a delta. This is the trade-off chosen over per-file
  diffing (which was hitting 1000+ individual requests for `modules/`+`mods/`
  alone, before `data/` was even added).
- `otclient` / `otclient-launcher` binaries — only if the binary itself
  actually changed (i.e. you rebuilt with different code).

## One-time production setup (already done, documented for reference / a future server)

1. **Web server + PHP + HTTPS already working** — reused the existing MyAAC
   deployment, nothing launcher-specific needed here.
2. **Receiving directory**, owned so your SSH user can write without `sudo`
   every time:
   ```bash
   sudo usermod -aG www-data $(whoami)   # then reconnect SSH for it to take effect
   sudo mkdir -p /var/www/html/client-releases/current/linux
   sudo chown -R www-data:www-data /var/www/html/client-releases
   sudo chmod -R 2775 /var/www/html/client-releases   # setgid: new files inherit www-data group
   ```
3. **`/var/www/html/launcher-manifest.php`** — NOT part of this git repo
   (it's website-side, lives outside the client repo entirely), so it has to
   be created by hand on any new server. Minimal, no MyAAC bootstrap, no DB:
   reads `dist/linux/manifest.json` (published there by step 2 above),
   fills in the request-specific absolute download URL, echoes it back.
   ```bash
   sudo chown www-data:www-data /var/www/html/launcher-manifest.php
   ```
4. **Check for a blanket file-extension block** in the web server config
   (a rule like `location ~* \.(?:json|log|sql|bak|...)$ { deny all; }`,
   meant to stop leaking backup/config files, that can also catch legitimate
   `.json` files this system serves under `client-releases/`). Fedora dev
   box had one and needed a narrow `/client-releases/` exemption
   (`tools/setup-nginx-client-releases-exemption.sh`); production's nginx
   config turned out not to have this rule at all, so nothing was needed
   there — but it's worth checking on any new server.
5. **`launcher.cfg`** on whatever machine runs the launcher:
   ```
   update_url=https://<your-domain>/launcher-manifest.php
   client_executable=otclient
   client_args=
   ca_cert_path=
   allow_insecure_http=0
   ```

## Verifying a release actually landed correctly

```bash
curl -s -X POST https://<your-domain>/launcher-manifest.php -d '{"os":"linux"}'
```
Should return the real manifest (checksums, archive list) — `{"error":"No
release published for platform: linux"}` means the sync hasn't happened yet
or landed in the wrong directory.

```bash
curl -s https://<your-domain>/client-releases/current/linux/data.zip -o /tmp/check.zip
sha256sum /tmp/check.zip   # compare against the "data" entry's checksum in dist/linux/manifest.json
```
Confirms a real download round-trip matches what was published, not just
that the manifest file exists.
