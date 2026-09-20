# Spec & Runbook: Coop Media (Sovereign Media Hub & Content Server)

Per rebuild-brief.md rule 5: written procedure first. Reversible-lane
(rule 4) — an additive read-only media server, Go static binary, and edge
Caddy route. Reverts in seconds with no schema or data consequences.

---

## 1. Context & Architectural Intent

### The Problem
Members capture photos, shoot home videos, record audio, and collect digital music
and documents across smartphones, laptops, and field recorders.
Existing content solutions fail the cooperative model:
1. **Surveillance cloud lock-in:** Cloud platforms (Spotify, Apple Music/iCloud,
   Google Photos, Netflix) charge subscription rents, scan media for profiling,
   and revoke member access at will.
2. **Heavyweight self-hosted sprawl:** Popular self-hosted servers (Jellyfin, Plex,
   Immich, Navidrome, Nextcloud) require multiple containers, heavy runtimes (.NET,
   Python, Node), external relational databases (PostgreSQL/SQLite), and background
   scrapers consuming 1–3 GB RAM, creating frequent maintenance and database sync friction.
3. **Fragile client sync agents:** Proprietary background sync apps drain device
   batteries and corrupt local client databases.

### The "Smart Server, Stateless Edge" Philosophy (The Sun Ray Model)
Per [Platform Patterns](patterns.md) and [Design Lens](design-lens.md):
> *"Smart Server, Stateless Edge: The server is the center of gravity; client
> devices are thin, interchangeable presentation surfaces."*

`coop-media` implements this philosophy as a unified sovereign content hub:
1. **Zero Edge Toil:** Members deposit media using standard, native OS file tools
   over SMB (`//core-node.coop.internal/share/media`) from macOS Finder, Windows File Explorer,
   Linux, or iOS/Android Files apps without any custom client daemons.
2. **Server-Side Direct Streaming:** The server extracts EXIF camera metadata,
   ID3v2/Vorbis music tags, generates responsive thumbnails, and streams audio/video
   via HTTP 206 byte-ranges for instant seeking with zero transcoding overhead.
3. **Safe Metadata Curation:** Member media files remain strictly read-only.
   User-assigned metadata, tags, and custom artwork are stored separately in
   `/var/lib/coop-media/metadata/`, guaranteeing that no software action can ever
   corrupt or alter original member files.
4. **Instant Presentation Surface:** Pure semantic HTML5 + vendored htmx. Loads in
   <25ms with near-zero CPU and memory footprint (~25 MB RAM).

---

## 2. Specification

### Content Roots & Permissions
1. **Shared Media Root:** `/srv/share/media`
   - Owned by `root:share-users`.
   - Permissions: `2775` (`drwxrwsr-x` — setgid bit set so subdirectories inherit group).
   - Structured subdirectories:
     - `/srv/share/media/photos` — Albums, events, camera uploads.
     - `/srv/share/media/videos` — Home videos, short films, community recordings.
     - `/srv/share/media/music` — Audio tracks, albums, podcasts, audiobooks.
2. **State & Metadata Store:** `/var/lib/coop-media`
   - Owned by `coop-media:coop-media`, mode `0750`.
   - Stores user-assigned metadata overrides, tags, and custom artwork in `metadata/<id>.json`
     and `art/<id>.*`.
   - Included in daily restic backups.
3. **Thumbnail Disk Cache:** `/var/cache/coop-media`
   - Owned by `coop-media:coop-media`, mode `0750`.
   - Stores pre-computed JPEG/WebP thumbnails and extracted cover art.
4. **Multi-Tenant Storage & Isolation Boundaries:**
   - **Single Unified SMB Share:** All member private folders and collective media stick strictly to the single canonical Samba share `[share]` (`/srv/share`, accessed as `smb://core-node.coop.internal/share`). No standalone shares are created outside of `[share]`.
   - **General Shared Media Subfolder:** `/srv/share/media` (mode `2775 root:share-users`, accessed as `smb://core-node.coop.internal/share/media`) holds the collective cooperative media library (photos, videos, music). Items have `owner: ""` and are browsable by all members and LAN guests.
   - **Personal Member Subfolders:** `/srv/share/{username}` (mode `0700 {uid}:share-users`, accessed as `smb://core-node.coop.internal/share/{username}`) holds private member data.
   - **Least-Privilege POSIX ACLs:** Instead of blanket kernel bypass capabilities (`CAP_DAC_READ_SEARCH`), `coop-media` is granted targeted read-only traversal via POSIX ACLs (`setfacl -R -m u:coop-media:rX /srv/share/{username}`). Mode `0700` remains intact on the directory permissions, ensuring cross-member access remains completely denied over SMB.
   - **Strict Multi-Tenant Application Authorization:**
     - Items discovered in a member's personal share are assigned `owner: "{sAMAccountName}"` (e.g. `steward.lead`).
     - Unauthenticated requests can **never** see, search, or stream personal items.
     - Authenticated members see the general shared library (`owner: ""`) PLUS their own personal library (`owner: "{session.username}"`).
     - Cross-member access is strictly blocked: requests for another user's personal media (raw streaming, thumbnails, metadata, or modals) return `HTTP 403 Forbidden`.

### Supported Media Formats
| Media Type | Extensions | Capabilities & Processing |
|---|---|---|
| **Photos** | `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp` | EXIF metadata extraction (date, camera, exposure, orientation); on-demand thumbnail generation; lightbox modal viewer. |
| **Videos** | `.mp4`, `.mov`, `.m4v`, `.webm`, `.mkv` | HTML5 `<video controls playsinline>` player; HTTP byte-range support (`206 Partial Content`) for instant seeking without downloading the full video; poster/badge display. |
| **Audio** | `.mp3`, `.m4a`, `.flac`, `.ogg`, `.wav` | Pure-Go ID3v2/Vorbis/MP4 tag extraction (Title, Artist, Album, Year, Track, Genre, embedded album art); in-browser persistent audio player with scrubber and playlist navigation. |

### Metadata Model & Tagging
1. **Tier 1 (Automatic Extraction):**
   - Extracts embedded tags directly from media files (EXIF for photos, ID3v2 for MP3, Vorbis for FLAC/OGG, MP4 atoms for M4A).
   - Embedded album art (APIC/PICTURE/covr) is extracted and cached for display.
2. **Tier 2 (Local Sidecars):**
   - Automatically detects folder artwork (`cover.jpg`, `folder.jpg`, `poster.jpg`) and companion `.nfo`/`.json` descriptors.
3. **Tier 3 (User Assignment & Tagging):**
   - Web UI modal allows editing Title, Artist/Creator, Album/Series, Year, Genre, Tags (e.g. `#favorites`, `#family`), and Synopsis.
   - Saves to `/var/lib/coop-media/metadata/<id>.json` without touching `/srv/share/media`.
4. **Instant Multi-Field Search:**
   - Searches across Title, Artist, Album, Year, Tags, Filename, and Folder hierarchy in <1ms.

### Uniform Module Interface (ADR 0001)

#### Human Interface (`/media/ui/*`)
- `/media/ui/` — Main media dashboard with type filter tabs (`All`, `Photos`, `Videos`, `Audio`, `Folders`), instant search bar, and persistent audio dock.
- `/media/ui/items?type=...&q=...&folder=...` — Filtered/searched media grid (htmx swap).
- `/media/ui/modal?id=...` — Lightbox modal for enlarged photos/videos with detailed metadata and download.
- `/media/ui/meta-editor?id=...` — Metadata and tag editing modal.

#### Machine / Health Interface (`/media/api/*`)
- `/media/api/health` — JSON status: service health, total items, media counts by type, cache size, uptime.
- `/media/api/items` — JSON list of indexed media items.
- `/media/api/item?id=...` — JSON metadata for a single item.
- `/media/api/item/metadata` (POST) — Persist user-edited metadata and tags.
- `/media/api/rescan` (POST) — Synchronously rescan `/srv/share/media`.

#### Raw Media Streaming (`/media/raw/*`)
- `/media/raw/thumb?id=...` — Scaled thumbnail or extracted album art (JPEG/PNG/SVG).
- `/media/raw/media?id=...` — Original media stream with HTTP 206 byte-range seeking.

---

## 3. Security Architecture & Threat Model

1. **Least-Privilege Execution:**
   - Dedicated unprivileged system user `coop-media` (`--system --no-create-home --shell /usr/sbin/nologin`).
   - Member of group `share-users` for read-only access to `/srv/share/media`.
2. **Zero Linux Capabilities:**
   - No `CAP_DAC_READ_SEARCH` or `CAP_DAC_OVERRIDE`. Cannot bypass kernel DAC permissions on member folders (`0700`).
3. **Systemd Sandboxing:**
   - `NoNewPrivileges=yes`
   - `ProtectSystem=strict`
   - `ProtectHome=yes`
   - `PrivateTmp=yes`
   - `ReadOnlyPaths=/srv/share/media`
   - `ReadWritePaths=/var/cache/coop-media /var/lib/coop-media`
4. **Network Scoping:**
   - Binds to `127.0.0.1:9096` (internal loopback interface).
   - Edge Caddy proxies `/media/*` with TLS, security headers, and redirects `/photos/*` to `/media/ui/`.

---

## 4. Operational Runbook

### Step 1: Storage Staging on `core-node`
```bash
# 1. Create media directory and subfolders on NVMe share
sudo mkdir -p /srv/share/media/photos
sudo mkdir -p /srv/share/media/videos
sudo mkdir -p /srv/share/media/music

# 2. Migrate existing photos into /srv/share/media/photos
if [ -d /srv/share/photos ] && [ "$(ls -A /srv/share/photos 2>/dev/null)" ]; then
    sudo mv /srv/share/photos/* /srv/share/media/photos/ 2>/dev/null || true
    sudo rm -rf /srv/share/photos
fi

# 3. Set group ownership and setgid permissions
sudo chown -R root:share-users /srv/share/media
sudo chmod 2775 /srv/share/media
sudo find /srv/share/media -type d -exec chmod 2775 {} +

# 4. Provision metadata and cache directories
sudo mkdir -p /var/lib/coop-media/metadata
sudo mkdir -p /var/lib/coop-media/art
sudo mkdir -p /var/cache/coop-media
sudo chown -R coop-media:coop-media /var/lib/coop-media /var/cache/coop-media || true
sudo chmod 0750 /var/lib/coop-media /var/cache/coop-media
```

### Step 2: Build & Deploy Static Binary
From the development machine:
```bash
cd coop-media
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /tmp/coop-media .
scp /tmp/coop-media core-node:/tmp/coop-media.new
```

On `core-node`:
```bash
sudo install -m 0755 /tmp/coop-media.new /usr/local/bin/coop-media
rm -f /tmp/coop-media.new
```

### Step 3: Create Dedicated System User
On `core-node`:
```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin coop-media || true
sudo usermod -aG share-users coop-media
sudo chown -R coop-media:coop-media /var/lib/coop-media /var/cache/coop-media
```

### Step 4: Install Systemd Service Unit
Create `/etc/systemd/system/coop-media.service`:
```ini
[Unit]
Description=Coop Media Sovereign Content Server & Hub
After=network-online.target samba-ad-dc.service
Wants=network-online.target

[Service]
Type=simple
User=coop-media
Group=coop-media
SupplementaryGroups=share-users
Environment=PREFIX=/media
Environment=LISTEN_ADDR=127.0.0.1:9096
Environment=MEDIA_ROOT=/srv/share/media
Environment=CACHE_ROOT=/var/cache/coop-media
Environment=DATA_ROOT=/var/lib/coop-media
ExecStart=/usr/local/bin/coop-media
Restart=on-failure
RestartSec=5s

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadOnlyPaths=/srv/share/media
ReadWritePaths=/var/cache/coop-media /var/lib/coop-media
RestrictAddressFamilies=AF_INET AF_INET6

[Install]
WantedBy=multi-user.target
```

Disable old `coop-photos` and enable `coop-media`:
```bash
sudo systemctl stop coop-photos || true
sudo systemctl disable coop-photos || true
sudo systemctl daemon-reload
sudo systemctl enable --now coop-media.service
```

### Step 5: Update Edge Caddy & Health Checks
1. Update `/opt/edge-caddy/Caddyfile`:
   - Replace `/photos/*` proxy with `/media/*` proxy.
   - Add permanent redirect `/photos/*` to `/media/ui/`.
   - Update portal dashboard link to `Coop Media Hub`.
2. Reload Caddy:
```bash
sudo docker exec edge-caddy-caddy-1 caddy reload --config /etc/caddy/Caddyfile
```
3. Update `/usr/local/bin/health-check.sh` to check `coop-media`.

---

## 5. Health Signal & Automated Verification

### Verification Commands
```bash
# 1. Systemd unit state
systemctl is-active coop-media.service

# 2. Local loopback health endpoint
curl -s http://127.0.0.1:9096/media/api/health | jq .

# 3. Edge Caddy proxy route
curl -k -s https://core-node.coop.internal/media/api/health | jq .

# 4. Legacy redirect test
curl -k -s -I https://core-node.coop.internal/photos/ui/ | grep -i "location"
```

---

## 6. Disaster Recovery & Troubleshooting

1. **Media Storage (`/srv/share/media`):**
   - Automatically included in existing restic backup job (`/srv/share` is in the scheduled backup scope).
2. **Metadata & Custom Artwork (`/var/lib/coop-media`):**
   - Added to restic backup job.
3. **Thumbnail Cache (`/var/cache/coop-media`):**
   - Disposable; automatically regenerated on-demand if cache is wiped.
4. **Troubleshooting Commands:**
   ```bash
   sudo systemctl status coop-media.service
   sudo journalctl -u coop-media.service -n 50 --no-pager
   ```
