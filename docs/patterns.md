# Operational & Architectural Patterns

This document records recurring operational, networking, and systems patterns discovered during the implementation and verification of the cooperative infrastructure. In accordance with rebuild-brief §5 rule 2 (no premature taxonomies), this file does not predeclare module boundaries; rather, it is a running collection of real failure modes and technical insights.

The purpose of this catalog is to make recurring lessons visible as architectural patterns before they are rediscovered the hard way, and to flag where an operational pattern should be automated, codified into runbooks, or guarded against in tests.

Per-entry format: what was observed, the generalized pattern, the operational opportunity, and its current status (`applied` — acted on; `open` — noticed, active; `watching` — single occurrence, monitored).

---

## Local/loopback checks give false passes

**Observed:**
- **Observed:** `smbclient -L` from the host itself passed for both
  users; the first real remote connection then hung completely because `ufw`
  had no allow rules for Samba/AD ports. Loopback traffic bypasses the
  firewall entirely, so the local check never exercised the actual path a
  real client uses.
- **Observed:** a second local check (`smbclient -L`, listing only)
  also missed a directory-ownership bug that only surfaced when a client
  actually entered the share, not just listed it.

**Pattern:** a health check run from the same host, or that only exercises
part of a path (list vs. actually connect), can pass while the real user-facing
path fails. Two different bugs hid behind two different flavors of
this in the same session.

**Opportunity:** the file share runbook step 11 already
calls this out explicitly now ("not the host itself — loopback bypasses the
firewall entirely and will give a false pass"). Worth carrying forward as a
standing rule for every future module's runbook: the health signal (rebuild-brief
rule 9) must include at least one check that exercises the full real path from
an actual remote client, not just a same-host or partial check.

**Status:** applied (in file-share.md's own text) for this module; open as a
general habit for the next module's runbook.

---

## Never use CAP_DAC_READ_SEARCH or root privilege to bypass member storage isolation in unauthenticated services

**Observed:**
- **Observed:** `coop-library` was stood up as an unauthenticated web
  utility to index operational runbooks and server data. To allow the
  unprivileged service user to read files, `AmbientCapabilities=CAP_DAC_READ_SEARCH`
  was granted, and `SHARE_ROOT` pointed at `/srv/share`. This bypassed the
  `0700` DAC permissions that protected individual member folders (`/srv/share/<member-folder>`),
  indexing private photos and personal documents and exposing them publicly
  over the LAN at `/library/ui/` with zero authentication.

**Pattern:** using Linux capabilities (`CAP_DAC_READ_SEARCH`, `CAP_DAC_OVERRIDE`)
or running as root to work around read permission errors in an unauthenticated or
cooperatively shared service completely destroys the trust boundary between
public/shared assets and private member storage. If a service does not
authenticate the requesting user and verify per-user authorization against the
identity provider (AD DC / Samba), it must never be granted privileges to read
private user directories.

**Opportunity:**
1. Default all unauthenticated services to strictly non-private shared roots
   (e.g. `/opt/coop-docs`).
2. Hardcode configuration guards in daemons to reject scanning parent member
   storage trees like `/srv/share`.
3. Never use `CAP_DAC_READ_SEARCH` or `CAP_DAC_OVERRIDE` in systemd units for
   unauthenticated services; rely on normal Linux DAC permissions so the OS
   kernel strictly blocks unauthorized access.

**Status:** applied (contained immediately, capability stripped, service code
hardened and verified).

---

## Smart Server, Stateless Edge (The Sun Ray Pattern)

**Observed:**
- **Observed:** Client-side SPA frameworks and distributed sync clients
  (e.g. Nextcloud desktop/mobile sync) impose high recurring steward toil:
  client database corruption, offline sync conflicts, and excessive battery/CPU
  drain on client devices.
- **Observed:** In contrast, building `coop-library` and `blocky-ui` as
  pure-Go daemons serving semantic server-rendered HTML fragments via vendored
  htmx resulted in 0kb client build footprints, instantaneous response times,
  zero edge administration toil, and 100% server-side trust boundary enforcement.

**Pattern:** The more state, business logic, and compute pushed to edge client
devices (phones, laptops), the higher the recurring steward maintenance burden
and member friction. Shifting compute, storage, indexing, and rendering back to
the server (`core-node`) renders the client device a completely
interchangeable presentation surface ("dumb terminal"), eliminating edge support
tickets.

**Opportunity:**
Formalize the 5-Point "Sun Ray" Decision Filter in `docs/design-lens.md`:
1. *Edge Ephemerality:* If a client device drops in a river, no unique state is lost.
2. *Zero Edge Admin:* No proprietary sync daemons or client runtimes required.
3. *Presentation Surface Only:* Server-rendered HTML/htmx; no client SPA bloat.
4. *Compute Density:* Indexing, transcoding, and thumbnailing happen where data lives.
5. *Strict Server Trust:* Authorization enforced at POSIX DAC / kernel layer before data leaves the server.

**Status:** applied (ADR 0004, `docs/design-lens.md`, `coop-library`, `blocky-ui`).

---

## Distro packages split what upstream ships as one thing

**Observed:**
- **Observed:** Ubuntu splits the AD schema
  LDIF files (`samba-ad-provision`) and the actual AD DC service unit
  (`samba-ad-dc`) out of the base `samba` package. Provisioning failed twice
  before both were identified and installed.
- **Observed:** same exact gap hit again, from
  scratch, on a brand-new VM. Confirms this isn't a one-off fluke of the
  original install — it's a durable fact about this distro's packaging that
  will bite every fresh install of this module until the runbook itself is
  the thing people follow (which it now documents, per file-share.md step 3).

**Pattern:** a distro's packaging choices can silently omit pieces a service
needs to actually run in the mode you want, even though the package that
"sounds right" installs cleanly and the service appears to start.

**Opportunity:** when standing up a new piece of software on Debian/Ubuntu,
check the vendor's own docs for the packages it expects to exist, don't just
install the top-level package name and assume it's complete — verify the
specific binaries/units you need are present before moving on.

**Status:** applied (two occurrences now confirmed; file-share.md step 3
documents the fix, and it held on a from-scratch retry).

---

## Vendor gate scripts encode assumptions that don't hold on every version

**Observed:**
- **Observed:** Debian/Ubuntu's `/usr/share/samba/is-configured`
  script compares `testparm`'s output as an exact string, but this Samba
  version prints banner lines to stdout first, breaking the comparison and
  blocking `smbd` from starting even though the config was fine.

**Pattern:** a distro-provided gate/guard script can be wrong for reasons
that have nothing to do with your actual configuration. When a service
refuses to start for a reason that doesn't match what you can see in the
config, suspect the guard script before the config.

**Opportunity:** the fix already applied (a systemd drop-in blanking
`ExecCondition=`, not editing the vendor script) is the right general
response — override via drop-in, never patch a vendor-owned file in place,
since a package update silently reverts an edited file but not a drop-in.
Worth keeping as a default instinct for the next time a unit refuses to start
for a reason that looks like a bug rather than a real misconfiguration.

**Status:** applied.

---

## Permission/ownership settings only apply going forward, never retroactively

**Observed:**
- **Observed:** `force group = share-users` in smb.conf only affects
  newly created files; a share directory `mkdir`'d before that config existed
  stayed `root:root` and broke every connection at `vfs_ChDir` until manually
  `chown`'d.

**Pattern:** a config directive that governs future behavior is easy to
mistake for one that fixes existing state. Order-of-operations matters:
anything created before its owning config existed needs an explicit,
separate fix-up step, not just "the config is right now."

**Opportunity:** when a runbook step says "create X" followed later by "set
config governing X," add an explicit check: does X already exist from an
earlier step, and if so does its state need to be retroactively corrected?
file-share.md step 10 now documents this gotcha directly.

**Status:** applied (documented); open as a general runbook-writing habit.

---

## Manual troubleshooting leaves state that later breaks automation

**Observed:**
- **Observed:** the first scheduled `backup.sh` run failed because
  an earlier manual `restic check`/restore session left a stale repository
  lock. Left alone, this would have silently blocked every future scheduled
  backup with no visible symptom.

**Pattern:** hands-on debugging (checks, restores, manual runs) can leave
behind lock files, temp state, or partial artifacts that don't matter for a
one-off manual command but silently wedge the automated version of the same
task later, often with no error surfaced anywhere obvious.

**Opportunity:** any script that automates a previously-manual procedure
should defensively clear known-safe leftover state (a confirmed-dead lock,
not an in-progress one) at its own start, exactly as `backup.sh` now does
with `restic unlock`. Treat this as a checklist item when turning any
runbook's manual procedure into automation per rule 5.

**Status:** applied (in backup.sh); worth checking for on every future
manual-to-automated conversion.

---

## systemd "active" does not mean "ready" for multi-listener services

**Observed:**
- **Observed:** `samba-ad-dc` reports "active" to systemd as soon as
  its main process starts, but DNS/Kerberos/LDAP/SMB listeners come up in
  stages afterward. The first post-boot health check ran before port 445 was
  bound and failed, even though the service and all its other ports were
  genuinely fine.

**Pattern:** for any service that owns multiple listeners/subsystems,
"active" from systemd (or `After=` unit ordering) only guarantees the process
started, not that every dependent listener is bound yet. A one-shot check
run right after boot can catch this transitional window and report a false
failure.

**Opportunity:** health checks for multi-listener services should retry with
a short backoff window rather than check once, exactly as
[health-check.sh](health-check.sh) now does. Apply the same
retry-not-one-shot default to any future service's post-boot health check,
not just this one.

**Status:** applied.

---

## Live log tailing during a reproduced failure beats reading history after the fact

**Observed:**
- **Observed:** the real cause of "permission to access this
  server" (a `vfs_ChDir` permission error, not an auth problem) was found by
  running `journalctl -u samba-ad-dc -f` and retrying the connection live,
  not by reading logs after the fact.

**Pattern:** the troubleshooting sequence that actually worked, twice in this
session, was: reproduce the failure while tailing the relevant service's log
in real time, rather than guessing from symptoms or reading historical log
output cold.

**Opportunity:** worth stating as a default first move in the failure
procedure section of future runbooks — before trying fixes, reproduce while
tailing logs live, so the real error (which may differ from the client-side
symptom) surfaces directly.

**Status:** watching — true in this session's troubleshooting so far; confirm
it holds the next time a failure needs root-causing before promoting to a
standard runbook step.

---

## A wildcard bind on port 53 blocks any other service, on any address, anywhere on the host

**Observed:**
- **Observed:** `lxd init --auto` failed to create
  its managed bridge network because its dnsmasq couldn't bind port 53 on
  the bridge's own brand-new, never-before-used private IP. Root cause:
  `samba-ad-dc` binds DNS on `0.0.0.0:53` (all interfaces) system-wide, and
  a wildcard bind blocks any other process from binding port 53 on *any*
  specific address on the same host, even one that has nothing to do with
  Samba's own network. `dns.mode=none` on the LXD network didn't fix it
  either — had to abandon LXD-managed networking entirely and hand-build an
  unmanaged bridge instead.
- This is the same underlying fact as the already-known
  `systemd-resolved`-vs-`samba-ad-dc` conflict (file-share.md step 4,
  earlier in development), just showing up against a different competitor for the same
  port. The lesson generalizes past "disable systemd-resolved."

**Pattern:** once `samba-ad-dc` (or anything else doing a wildcard DNS
bind) is running on a host, that host cannot run *any* other service that
wants port 53 on *any* address, including brand-new private/virtual ones —
not just the obvious systemd-resolved collision, but LXD's per-network
dnsmasq, and presumably anything else with the same habit (Docker's
embedded DNS, other container runtimes, etc.).

**Opportunity:** this is directly relevant to the parked "network-wide
DNS/ad-blocking" item in the open issues backlog — that module, whenever it's
picked up, will hit this exact conflict on day one if it's placed on the
same host as the DC. Worth deciding up front whether it runs on different
hardware, or is integrated as a forwarder/zone within Samba's own DNS
rather than as a separate competing listener. Also worth a standing check
before adding *anything* new to this host: `ss -tuln | grep :53` before
assuming a fresh network/bridge/container will just work.

**Status:** confirmed — a third occurrence (during deployment):
a Docker container on this host couldn't get DNS answers from the DC even
once firewalled correctly (see the ufw-scoping pattern below, a related
but distinct issue) — worked around with a static `extra_hosts` entry
rather than chased further. Three unrelated pieces of software (a stub
resolver, an orchestrator's managed DNS, and — differently — plain
container DNS forwarding) have now all hit some version of "this host's
port 53 is not simply available," treat as a durable fact about this host,
not a fluke.

---

## Backup scope covers data, not the config needed to actually use it

**Observed:**
- **Observed:** the restic backup covers
  `/srv/share` and `/var/lib/samba` (the AD database/SYSVOL), which is the
  *data*. But bringing a restored DC to life on a fresh VM also needed
  `/etc/samba/smb.conf` and `/etc/krb5.conf` — neither of which is in the
  backup at all. Had to copy them from the live host by hand to get the
  drill working, which only worked because the live host happened to be
  reachable; a real disaster (live host gone) would have meant
  reconstructing smb.conf from the runbook and memory instead of restoring
  it.

**Pattern:** it's easy to define a module's backup scope around its
*state* (the database, the files) and forget the *configuration* that
makes that state usable — and this gap stays invisible right up until a
real restore is attempted, since every other check (backup completing,
`restic check`, even a file-level restore-and-diff) only ever looks at the
data that's already inside the backup's own scope.

**Opportunity:** either extend backup.sh's paths to include `/etc/samba`
and `/etc/krb5.conf`, or make a deliberate, documented choice that config
is reconstructed from the runbook instead — but make it a decision, not a
silent gap. Worth checking for on every future module: does "backup" cover
everything actually needed to bring the service back, or just its data?

**Status:** applied — Operational resolution: backup.sh now includes
`/etc/samba` and `/etc/krb5.conf`, confirmed present in a real snapshot via
`restic ls`. Still worth the general habit for every future module.

---

## A dry-run walkthrough predicts known gotchas well; it can't predict execution-context limits

**Observed:**
- **Observed:** a dry-run walkthrough for onboarding a new file-share user was
  written first, then actually executed against `core-node` for a real
  test account (`test.onboarding`). Comparing the two:

  **Correctly predicted, confirmed true on the real run:**
  - The bare-first-name folder convention (`user1`, `user2`) is genuinely
    undocumented and ambiguous — confirmed by `ls -la /srv/share` showing
    exactly that, no other convention recorded anywhere. Now fixed in
    file-share.md step 13.
  - `ufw` rules are shared, not per-user — the real run needed zero firewall
    changes for the new account, exactly as predicted.
  - `getent`/NSS still doesn't resolve winbind names; `wbinfo -i` was
    required, exactly as the existing pattern above describes.
  - `force group` does not retroactively (or ever) apply to a directory made
    with a plain `mkdir` — confirmed again on a *brand-new* folder, which
    sharpens the existing pattern above: this was never actually about
    *order* (config-before-vs-after the `mkdir`), it's that `force group`
    only ever governs objects created *through smbd*, full stop. Worth
    correcting that pattern's framing next time it's touched.

  **Not predicted — only surfaced by actually doing it:**
  - **Credential separation breaks the assumption that whoever sets up the
    account can also verify the login.** The real run generated the new
    account's password with `--random-password`, redirected straight to a
    root-only file on the server, and deliberately never let it reach the
    session doing the setup. That's the right way to handle a credential —
    but it means the "Health signal" section's per-user `kinit`/`smbclient`
    checks structurally cannot be run by the same actor that did steps 1-13.
    The dry-run walkthrough's "Check it worked" section assumed one person
    (or process) could do both; that's false as soon as password-handling is
    done correctly. Now documented in file-share.md's Health signal section.
  - **A freshly `mkdir`'d private folder may not be at parity with existing ones.**
    `ls -la /srv/share` shows a trailing `+` on established user folders (extra
    ACL metadata) that the newly created `test-onboarding` folder does not
    have. Root cause not confirmed — `getfacl` isn't installed on the host, so
    the actual ACL contents couldn't be inspected — but the working guess is
    that the `+` gets set the first time a real SMB client actually touches the
    folder, not by `mkdir`+`chown`+`chmod` alone. Unconfirmed; worth checking
    with `apt install acl` and a real client connection next time this runs,
    rather than assumed harmless.
  - **A real run surfaces incidental findings a dry run can't, just by
    reading live state.** Checking `ufw status` for an unrelated reason
    (confirming no new rule was needed) turned up stale ALLOW rules for
    80/tcp, 443/tcp, 9000/tcp — leftover from the v1 Docker stack
    decommissioned on earlier in development, never cleaned up. A dry run, working from
    documentation rather than the live host, has no way to catch drift
    between what's written down and what's actually still configured.

**Pattern:** a dry-run walkthrough, grounded carefully in existing docs, is
good at predicting *documented* gotchas and bad at predicting anything that
depends on *how* the real run is actually executed (who holds which
credential, what state already exists on the box that nothing wrote down).
The gap isn't a failure of the walkthrough — it's evidence that some things
are only knowable by doing the thing for real.

**Opportunity:** treat every dry-run-then-real-run pair as a two-sided check:
did the real run confirm the walkthrough's predictions (validates the docs
it was grounded in), and did it find anything the walkthrough couldn't have
known (a genuinely new finding, not a walkthrough mistake). Worth doing this
comparison explicitly, in writing, every time a runbook is executed after
being substantially rewritten or extended — not just trusting a clean run.

**Status:** watching — one comparison so far.

---

## Firewall rules scoped to the physical LAN don't cover container traffic

**Observed:**
- **Observed:** every existing ufw rule for
  Samba/AD ports (53, 636, etc.) was scoped to `10.0.0.0/24`, the
  physical LAN — because every prior client that needed one *was* on the
  physical LAN. A Docker container on this same host has a source IP in a
  completely different private range (172.x), so it silently failed both
  DNS and LDAPS with no error pointing at the firewall at all — it just
  looked like the service wasn't reachable.

**Pattern:** a firewall rule scoped to "the LAN" implicitly assumes every
legitimate local client arrives from that one physical subnet. Any
container/VM runtime on the same box (Docker, LXD, anything with its own
virtual bridge) is a *second* local network with its own address range,
invisible to a rule written before that runtime existed. This is the same
underlying shape as "local/loopback checks give false passes" above, one
layer removed: there it was loopback bypassing the firewall entirely, here
it's a real local network the firewall rules never anticipated.

**Opportunity:** before assuming a new local service (containerized or
not) can reach an existing one, check what source IP it'll actually use
and whether any existing firewall rule covers that range — don't assume
"it's all local, it'll be fine." Pinning new bridge networks to a fixed,
explicit subnet (rather than letting the runtime auto-allocate) makes the
resulting firewall rule stable and legible, matching how the existing LAN
subnet and the restricted VLAN were both deliberately chosen rather than
left to chance.

**Status:** watching — one occurrence so far (LAM/Docker); check for
recurrence the next time anything containerized needs to reach an
existing host service.

---

## Redirecting a secret away from your own view still needs the result checked

**Observed:**
- **Observed:** `samba-tool user create --random-password` was
  assumed to print the generated password, so its output was redirected
  straight to a root-only file, deliberately unread, as the credential-
  handling step for onboarding `test.onboarding`. This Samba version never
  prints the password at all — the file ended up containing only a generic
  success message, and combined with `--must-change-at-next-login`, the
  account was left with no known password at all, usable by no one.

**Pattern:** deliberately not looking at a secret (the right instinct, so it
never lands somewhere it shouldn't) is easy to conflate with "the step
worked." Redirecting output away from yourself removes your own ability to
notice the command didn't produce what you assumed it would. This is the
same root mistake as "an exit code of 0 isn't verification" (see the
restore-drill entries above) wearing a different costume: here the missing
check isn't the exit code, it's the *shape* of the hidden output.

**Opportunity:** when a command's output is being deliberately withheld from
the operator's own session (the correct move for a credential), still
verify the *result* without ever exposing the *value* — e.g. check the
target file is non-empty and roughly the expected length/format, or that
the account's own state changed in an observable, non-secret way
(`pwdLastSet`, `badPwdCount`, a "changed password OK" message from the tool
itself). Never treat "I redirected it somewhere I can't see" as equivalent
to "it worked." Worth a standing check for any future module that generates
and hides a secret (API keys, service-account passwords, TLS material).

**Status:** applied (fixed for test.onboarding via a script that generates,
uses, and writes the value entirely in one remote root shell, then confirms
via the tool's own "Changed password OK" and the file's changed size/mtime
— all without the value itself ever appearing in the operator's session).

---

## Diagnosing file access as root hides permission bugs the real process would hit

**Observed:**
- **Observed:** after mounting a config
  directory as a volume, LAM's web UI showed "the main config file does not
  exist." Every diagnostic run via `docker exec` — `file_exists()`,
  `is_readable()`, `stat`, `cat` — said the file was there and fine. All of
  those checks ran as root (`docker exec`'s default user) without noticing.
  The actual bug was a `chown -R root:root` on the mounted directory that
  locked out `www-data`, the user Apache's PHP process genuinely runs as —
  invisible to every check I'd run, because root can read anything
  regardless of the bug.

**Pattern:** this is the same *shape* as "local/loopback checks give false
passes" above — a check run with more privilege or from a different vantage
point than the real caller can pass while the real path fails — but the
specific mechanism (root vs. a service account's uid, not host vs. network)
is different enough to be worth its own entry rather than folding in
silently.

**Opportunity:** when debugging "a service can't see a file/resource" and
root-level checks pass, immediately re-run the identical check as the
*actual* runtime user (`docker exec -u <service-user>`, `sudo -u <user>`,
etc.) before concluding the file is fine. Don't stop at "I can see it" —
confirm "the process that needs it can see it." Worth folding into the
standing habit the loopback-pattern entry already names: verify from the
real caller's actual vantage point, not a more-privileged proxy for it.

**Status:** applied (root cause found and fixed by explicitly testing as
`www-data`); worth checking for on every future "container-exec diagnostics
say it's fine but the app disagrees" situation.

---

## A Docker `_FILE`-suffixed secrets env var only works if that specific image's entrypoint supports it

**Observed:**
- **Observed:** `postgres:16-alpine`
  correctly reads `POSTGRES_PASSWORD_FILE`, but `guacamole/guacamole`
  only reads `POSTGRESQL_PASSWORD` (plain) — passing it the `_FILE`
  variant was silently ignored, writing an empty password into
  `guacamole.properties`. Surfaced as a Postgres-side SCRAM auth error,
  not an obvious "unrecognized env var" failure, so it looked like a
  database problem rather than a webapp config problem.

**Pattern:** the `_FILE` suffix convention (read a secret from a
file path instead of the env var's own value) is a convention some
images' entrypoint scripts implement, not a Docker or Compose feature
that works everywhere automatically. Two images in the same compose file
can disagree about whether they honor it, with no error at all from the
one that doesn't — it just uses whatever the literal (unset) value of
the plain var was.

**Opportunity:** don't assume `_FILE` support carries across every
service in a compose file just because one image (often `postgres`,
`mysql`, or other official upstream images) supports it. Check the
specific image's own docs, or verify by inspecting its actual rendered
config after first start. When it's not supported, an `.env` file
(mode 600, referenced via compose variable substitution) is this
project's existing fallback — see LAM's `LAM_MASTER_PASSWORD` and
Guacamole's `PG_PASSWORD`, both in ad-admin-gui.md.

**Status:** applied (Guacamole switched to the `.env` pattern); worth
checking for on every future compose file that mixes multiple images'
secret-handling conventions.

---

## Caddy answers a request with an empty 200, not an error, when Host/SNI matches no configured site

**Observed:**
- **Observed:** testing the Guacamole
  REST API against `127.0.0.1:8444` (instead of the Caddyfile's actual
  configured site addresses, `core-node.coop.internal` and
  `10.0.0.10`) got HTTP 200 with an empty body and no error at all.
  Looked exactly like a broken backend until the same request, sent
  directly to the guacamole container inside the Docker network,
  returned a correct real response — which is what actually isolated the
  bug to Caddy's routing, not the app.

**Pattern:** a reverse proxy that routes by Host/SNI can fail closed in a
way that's indistinguishable from the backend being broken — no 4xx, no
error page, just an empty success-looking response — if the test request
doesn't address it the way a real client would. This is the same *shape*
as "local/loopback checks give false passes" above (a check taken from
the wrong vantage point passes or fails misleadingly) but the specific
mechanism is proxy host-matching, not network path.

**Opportunity:** when debugging "the app behind Caddy isn't responding
right," first confirm you're actually hitting one of the Caddyfile's own
configured site addresses — not `localhost`, not a bare IP if the site
block only names a hostname, not a port number alone. If that's already
right, then suspect the backend; if not, fix the test before chasing a
backend bug that may not exist.

**Status:** applied (caught during Guacamole's own deploy); worth a
standing first-check for any future "reverse-proxied app returns nothing"
debugging session.

---

## Docker's own iptables rules for published ports sit ahead of ufw, regardless of ufw's policy

**Observed:**
- **Observed:** neither LAM's port 8443 nor
  Guacamole's port 8444 has an explicit ufw ALLOW rule, yet both are
  genuinely reachable from the LAN (confirmed for LAM by testing from a
  separate machine; confirmed for Guacamole from the host) despite ufw's
  default policy being `deny (incoming)`.

**Pattern:** Docker inserts its own DNAT rules for every `ports:`
mapping ahead of where ufw's INPUT chain filtering applies, so a
published container port is reachable from anywhere that can route to
the host's address regardless of what ufw's rule list says. This is a
widely-documented Docker/ufw interaction, not specific to this project —
but it means every ufw rule written so far for a *containerized* admin
tool (LAM, Guacamole) has been decorative, not load-bearing. The actual
LAN-only restriction on both tools is coming entirely from network
topology (no route from outside the LAN to `10.0.0.0/24`), not from
this host's own firewall.

**Opportunity:** decide, explicitly, whether that's an acceptable trust
boundary for admin tools this sensitive (Guacamole fronts RDP to a
domain-joined Windows VM; LAM can edit AD user/group objects) or whether
ufw needs the standard fix (rules in the `DOCKER-USER` chain, which
Docker respects, instead of the top-level chains ufw manages by
default). Not done as part of either deployment — affects LAM
retroactively too, so it's a decision for the author, not something to
silently patch mid-task.

**Status:** watching — confirmed present for two services now (LAM,
Guacamole); worth resolving with an explicit decision before a third
containerized admin tool goes on this host.

---

## A reverse proxy that strips a matched path prefix breaks a backend that was written expecting it preserved

**Observed:**
- **Observed:** moving LAM and Guacamole
  behind one shared Caddy, `handle_path /lam/* { reverse_proxy lam:80 }` and
  the same for `/guacamole/*` strips the matched prefix before forwarding
  (Caddy's documented behavior for `handle_path`). Both backends broke: LAM
  returned a 302 redirect loop back to the same URL, Guacamole returned a
  flat 404. Confirmed root cause by hitting `guacamole:8080/` directly from
  inside the edge Caddy container (404) versus `guacamole:8080/guacamole/`
  (200, real app) — the backend itself expects to be addressed at the same
  path the outer proxy was matching on, not at `/`. Fixed by switching both
  blocks to plain `handle` (path preserved, full original path forwarded to
  the backend), matching exactly what each tool's own prior single-site
  Caddy already did before consolidation.
- Same underlying shape, two backends, in the same session — meets the
  two-occurrence bar directly.

**Pattern:** `handle_path` and `handle` look interchangeable for routing
("requests under this prefix go here") but differ in what the backend
receives, and a backend can be written assuming either one. Guacamole's
Tomcat and LAM's Apache config both expect the full `/toolname/` path,
because that's how each was originally fronted (`reverse_proxy` with no
prefix-stripping middleware). Consolidating multiple single-site proxies
into one multi-path proxy is not a purely mechanical merge — each backend's
assumption about its own mount path has to be checked, not inferred from
how the routing "should" work.

**Opportunity:** when merging two previously-independent reverse-proxy
configs into one, check what path each backend actually expects (a quick
`curl`/`wget` straight to the backend, at `/` and at its old mount path, in
the same style as the "Caddy answers an empty 200" entry above) before
assuming a prefix-based `handle_path` split is correct. Default to `handle`
(path preserved) unless there's a specific reason to strip — it matches
what most containerized web apps that ship with a fixed context path
actually expect.

**Status:** applied (both LAM and Guacamole fixed via `handle` instead of
`handle_path`, verified against each app's actual response body — not just
an HTTP 200, since a proxy misconfiguration can still return 200 for the
wrong content).

---

## A paravirtual disk bus can make the driver-delivery media itself unreadable by the OS that needs the driver

**Observed:**
- **Observed:** LXD VM disk devices default
  to `virtio-scsi-pci`. Windows has no in-box driver for that bus, and this
  applies uniformly to *every* device on it — including whichever ISO was
  meant to carry the fix. A genuinely circular trap: nothing on the bus is
  readable until the driver loads, and the driver can't be read until
  something on the bus is readable. Only worked around by moving the
  driver-delivery media to a bus Windows already has an in-box driver for
  (`io.bus: nvme`) — but that surfaced a second trap: an **ISO file**
  attached over NVMe shows up as a correctly-sized raw disk in `diskpart`
  but with zero mountable volumes, because NVMe has no CD-ROM device class
  and Windows never runs ISO9660 recognition against it. Only a real
  partitioned filesystem (FAT32 with an actual MBR, not a bare
  `mkfs.vfat`-on-a-file "superfloppy") worked as the actual driver payload.

**Pattern:** when a paravirtual/passthrough bus requires a guest driver the
OS doesn't ship in-box, don't assume "attach the fix on a different, safer
bus" is a complete fix on its own — the *format* of what's on that bus
matters too, and an ISO image specifically may not behave the way it does
on its native/expected bus once moved.

**Opportunity:** for any future guest OS install needing out-of-box drivers
on a paravirtual platform (not just this Windows/LXD case), check early
whether the driver-delivery media needs to be a real filesystem image
rather than an ISO, before assuming a bus change alone solves visibility.

**Status:** applied — see
the AD administration VM runbook (§6a)
for the exact working recipe (partition table, tools, device config).

---

## An installer's device scan can be a one-shot snapshot that never re-checks — and closing it can force a restart that erases the fix

**Observed:**
- **Observed:** Windows Setup's "Install
  driver to show hardware" screen appears to invite retrying (Browse,
  Install, a visible driver list) but its underlying disk scan ran once,
  early, and never updates — confirmed by loading the actual driver live
  (`drvload`) mid-session, confirming via `diskpart` that the target disk
  was genuinely visible at the OS level, and watching the *same* screen
  still report the identical failure with `Back` greyed out. Starting a
  second instance of the installer didn't help either (single-instance
  lock, silently no-ops). Closing the stuck instance did work — except
  Setup was the shell's only configured app (WinPE `winpeshl.ini`), so
  exiting it triggered a full guest restart, which erased the
  session-volatile driver load and reproduced the exact same stuck state
  from scratch.

**Pattern:** a stuck wizard/installer screen that looks like it should
re-evaluate on retry may not — and the "obvious" way to force a fresh
instance (close and relaunch) can trigger side effects (here: a full OS
restart) that undo whatever you just fixed to get past it. Worth checking
whether the environment auto-launches the stuck process as its *only* job
(a shell, an entrypoint, a single-app kiosk config) before assuming closing
it is free.

**Opportunity:** when a wizard/installer appears stuck despite the
underlying condition being fixed, check first whether the fix needs to
happen *before* that process's first pass runs (e.g., earlier in an answer
file / init sequence) rather than trying to nudge the already-running,
already-stuck instance.

**Status:** applied — the working fix (`RunSynchronousCommand` running
`drvload` before Setup's own disk scan) is in
the AD administration VM runbook (§6a).

---

## A host-side macvlan shim with a lower route metric silently steals reply-source for unconnected UDP sockets

**Observed:**
- **Observed:** `core-node` has `macvlan0@eth0`
  (`10.0.0.15`), LXD's host-side shim for reaching the `admin-vm` VM.
  It held a `10.0.0.0/24` route with an implicit metric of 0, beating
  `eth0`'s own route (metric 100, its real LAN address). Any service bound
  to `0.0.0.0` on an unconnected UDP socket — Samba's DNS server, in this
  case — had its replies sourced from `.115` instead of the address a
  client actually queried (`.110`), because the kernel picks a reply source
  address from the routing table rather than echoing the packet's original
  destination unless the application explicitly captures it. `dig` rejected
  the mismatched source outright (its own spoofing protection); a real
  client's resolver would do the same, just less legibly. TCP was
  unaffected — a connected-socket accept() fixes the source address at
  the tuple, no routing ambiguity involved — which is exactly why the
  edge-Caddy work the day before (all TCP) tested clean and this didn't
  surface until a UDP-based service was actually pointed at from off-host.

**Pattern:** a host-side networking shim added for one specific purpose
(here: letting the host reach its own macvlan child, which the kernel
can't do directly) can silently win the routing table's default-metric
tiebreak for the *entire* subnet it happens to share, not just the one
address it exists for — and the failure mode only shows up for unconnected
UDP replies, not TCP, so a thorough-looking TCP-only verification pass can
completely miss it. Same underlying shape as "firewall rules scoped to the
physical LAN don't cover container traffic" and the wildcard-port-53-bind
entry above — a virtual interface interacting with something that assumed
a single, simple LAN presence — but the specific mechanism (route metric
ordering, not a bind conflict or a firewall scope gap) is different enough
to log separately.

**Opportunity:** when a host gains a second interface/address on the same
subnet as its primary one (a macvlan shim, a VPN concentrator, anything
similar), check `ip route show` for duplicate-prefix routes and their
metrics before trusting any UDP-based service's LAN-facing behavior —
don't assume TCP-only testing generalizes. The fix (demote the shim's
route metric with `ip route replace`, being careful that a plain
`ip route replace <prefix> ... metric N` on a kernel-proto route without
your metric doesn't actually collide with the original — it can add a
second route instead of replacing it, needing an explicit `ip route del`
of the original) is durable within the current boot, but **not yet
confirmed to survive a reboot or a VM restart** — LXD likely recreates the
shim (and its default metric) on those events. Worth checking after the
next `admin-vm` restart, not assumed fixed for good.

**Status:** applied for the current boot; persistence unconfirmed. See
the LAN DHCP/DNS rollout documentation for the full
sequence, including the Samba DNS registration bug (a separate, if
related, issue) found in the same session.

---

## A macvlan guest can't reach its parent host's primary IP — so it's the wrong client to verify a host-provided LAN service

**Observed:**
- **Observed:** once the LAN's DHCP DNS option pointed at
  `core-node`'s real address (`10.0.0.10`), the `admin-vm` VM received
  `.110`/`.1` via DHCP correctly but every `nslookup` against `.110` timed
  out — while the same VM against `.115` (the `macvlan-shim` host shim)
  resolved `core-node.coop.internal` → `.110` and forwarded internet
  queries fine. Cause: Linux macvlan isolates a guest from the parent
  interface's own IP, so the guest's packets to `.110` never reach `eth0`
  at all — not a firewall or Samba issue. The `.115` shim exists precisely
  to give the host an address the macvlan guest *can* reach.
- A stale static `.115` DNS entry left on the VM as an earlier workaround
  briefly masked all of this during testing; removing it exposed the real
  `.110` timeouts (same shape as "manual troubleshooting leaves state that
  later breaks automation" above, wearing a masking-during-verification
  costume).

**Pattern:** a macvlan guest cannot use its parent host's primary address,
which makes it structurally the wrong client to verify any host-provided
LAN service living on that primary address. It passes via the shim and
fails via the real address for reasons that have nothing to do with the
service under test. This is the guest→host companion to the shim
reply-source entry directly above — same macvlan cast, opposite direction —
and the same family as "local/loopback checks give false passes" and
"diagnosing file access as root hides permission bugs": a check taken from
a vantage point the real user never uses.

**Opportunity:** verify LAN-wide services aimed at the host's primary IP
from a genuine physical client (or any non-macvlan-on-this-host client),
never from a macvlan guest of that same host. For the macvlan guest's own
resolver, point it at the shim address (`.115`) — and note that address's
durability is the same open caveat as the entry above (the shim/route isn't
yet proven to survive a reboot or VM restart).

**Status:** applied — one occurrence. The physical-client verification this
entry recommends was done earlier in development (a client laptop on wifi resolved via `.110`
correctly), confirming the VM was simply the wrong vantage point. The lesson
stands for every future host-provided LAN service: don't verify it from a
macvlan guest of that host. See
the LAN DHCP/DNS rollout documentation.

---

## `smbcontrol reload-config` does not reload Samba's internal DNS forwarder

**Observed:**
- **Observed:** after changing `dns forwarder` in `smb.conf` from
  `10.0.0.1` to `127.0.0.1:5300 10.0.0.1` (pointing Samba at the new
  Blocky filtering resolver), `testparm -s` showed the new value and
  `smbcontrol all reload-config` ran cleanly — but a known-blocked domain
  (`doubleclick.net`) still resolved to real IPs through `.110`, and a probe
  confirmed **zero** queries reached Blocky. `smbcontrol reload-config`
  reloads smbd/winbind; the internal DNS server task keeps the forwarder it
  read at daemon start. A full `systemctl restart samba-ad-dc` made the change
  take effect immediately (`doubleclick.net` → `0.0.0.0`).

**Pattern:** a `dns forwarder` change (and likely other settings the internal
DNS task reads only at startup) needs a `samba-ad-dc` **restart**, not a
config reload. A reload that returns success is not evidence the running DNS
picked the change up — prove forwarding with a real query (a known-blocked or
unique name through Samba's `:53`, watching for the answer that only the new
forwarder would give), not by trusting `testparm` + reload. Restarting
`samba-ad-dc` is a brief SMB/AD/file-share interruption, so plan forwarder
changes for a low-traffic window. Combine with the staged-startup pattern
below: after the restart Samba reports `active` before its DNS listener binds,
so retry the first lookups.

**Status:** `applied` — the DNS filtering runbook
Path A step 5 now says restart (required), not reload; health-check.sh gained a
through-Samba filtering probe that would catch a forwarder that silently
reverted.

---

## AppArmor restricts fusermount3 mount destinations

**Observed:**
- **Observed:** Attempting to run `restic mount` to `/var/backups/samba/mount`
  failed with `fusermount: mount failed: Permission denied`, despite running as root
  with `user_allow_other` enabled. `dmesg` confirmed AppArmor blocked the mount
  operation (`apparmor="DENIED" operation="mount" ... name="/var/backups/samba/mount/" error=-13 profile="fusermount3"`).
  Inspecting `/etc/apparmor.d/fusermount3` showed that Ubuntu restricts mount targets
  to specific standard paths: `@{HOME}/**/`, `/mnt/{,**/}`, `/media/**/`, `/tmp/**/`,
  and `@{run}/user/@{uid}/**/`.

**Pattern:** On Ubuntu/Debian systems enforcing AppArmor for `fusermount3`, FUSE
filesystems mounted via `fusermount3` cannot mount to arbitrary filesystem paths
(like `/var/...`) without altering vendor AppArmor profiles. Placing FUSE mounts under
standard `/mnt/...` paths succeeds immediately without modifying system profiles.

**Opportunity:** Use `/mnt/...` (e.g. `/mnt/backups-mount`) as the canonical mountpoint
for system FUSE mounts rather than non-standard paths under `/var` or `/srv`.

**Status:** `applied` — `restic-mount.service` and `coop-backup` target `/mnt/backups-mount`.

---

## Replacing a bind-mounted file may require container recreation

**Observed:**
- earlier in development (Blocky admin UI deployment) — replacing the host's
  `/opt/edge-caddy/Caddyfile` with `install` updated the host file, but the
  running Caddy container continued to see the old contents because the file
  bind mount retained the old inode. `caddy reload` therefore loaded the old
  configuration and returned success.

**Pattern:** when a container consumes a single-file bind mount, verify the
  file from inside the container after any replacement. If the container still
  sees the old inode, recreate the container with `docker compose up -d
  --force-recreate` (or update the mounted file in place) before reloading the
  service. A successful reload is not proof that the mounted source changed.

---

## Open opportunities not yet acted on

Pulled from the above, collected in one place:

- Add "verify from a real remote client, full path, not loopback or partial"
  as a standard line item in the health-signal section template for every
  future module's runbook (pattern: local/loopback false passes).
- Add "check vendor docs for split/companion packages before assuming a
  top-level package name is complete" as a standard pre-install step
  (pattern: distro package splits) — only one occurrence so far, watch for a
  second before treating as confirmed.
- Confirm the `macvlan-shim` route-metric fix survives the next `admin-vm` VM
  restart or host reboot; if LXD resets it, needs a durable fix (a systemd
  oneshot matching the `docker-user-firewall.service` pattern, or an LXD
  network config option if one exists) instead of a one-off `ip route`
  (pattern: macvlan shim route metric).
- Add "reproduce live while tailing the service's log" as the first line of
  every runbook's failure-procedure section, ahead of specific fixes (pattern:
  live log tailing).
- Before the next paravirtual guest-OS install needing out-of-box drivers,
  check early whether driver-delivery media needs to be a real partitioned
  filesystem (not an ISO) on the safe bus, and whether the fix needs to
  land before the installer's first device scan rather than after (pattern:
  paravirtual bus driver chicken-and-egg; pattern: one-shot device scans).
- Decide where "network-wide DNS/ad-blocking" actually runs before starting
  it — same host as the DC guarantees a port-53 collision (pattern: wildcard
  port 53 bind).

- Decide, explicitly, whether Docker/container-sourced traffic gets its own
  standing firewall convention (a documented default subnet range that's
  always allowed for specific ports) instead of rediscovering the gap
  per-service (pattern: firewall rules scoped to the physical LAN).

**Unresolved, not yet a pattern (root cause unknown, two occurrences that
may or may not share a cause — worth comparing next time either recurs):**

- **Observed during restore drill:** SMB session-setup over a bridged/virtio
  network path (LXD VM ↔ container, isolated bridge) failed cleanly after
  a successful NEGOTIATE, regardless of auth mechanism; the identical
  config works over loopback and works in production over the real LAN.
  See the disaster recovery drill record for everything ruled out
  (offload, MTU, encryption, Kerberos vs. NTLM, self-connection vs.
  separate peer). Accepted per author's decision (documented in recovery drill
  "decision" entry) — the module's actual restore-verification requirement
  was already met by other evidence.
- **Observed during LAM deployment:** DNS (UDP/53) queries from a Docker container
  to the DC left the container and arrived at the host's bridge (confirmed
  via packet capture) but never got a response — despite the identical
  source successfully reaching TCP/636 moments after the ufw fix. Worked
  around with a static `extra_hosts` entry rather than chased further.

Both are "traffic from an isolated/virtual local network to the host's own
address behaves inconsistently by protocol, for reasons not yet
understood" — different runtimes (LXD vs. Docker), different protocols
(SMB/TCP vs. DNS/UDP), so possibly unrelated, but the shared shape is
suspicious enough to note. Worth raising with someone who's hit either
exact failure mode (real technician feedback) before spending more
unstructured solo debugging time on either.
