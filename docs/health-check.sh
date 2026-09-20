#!/bin/bash
# Health check script for core cooperative services:
# Samba4 Active Directory Domain Controller, Kerberos, DNS, Blocky ad-filtering,
# and bespoke Go/htmx micro-utilities.
#
# Exit code 0 = all checks passed. Non-zero = at least one failure.

set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1"
    local rc="$2"
    if [ "$rc" -eq 0 ]; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

# 1. The AD DC daemon must be active.
systemctl is-active --quiet samba-ad-dc
check "samba-ad-dc is active" $?

# 2. smbd must stay disabled — on an AD DC installation, the internal file server
#    is run directly by samba-ad-dc.
if systemctl is-active --quiet smbd; then
    check "smbd is disabled (found ACTIVE instead)" 1
else
    check "smbd is disabled" 0
fi

# 3. Core AD/Samba ports actually listening. Retried, not one-shot — on a
#    fresh boot, samba-ad-dc reports "active" to systemd as soon as its
#    main process starts, but its internal listeners (DNS, Kerberos, LDAP,
#    SMB) come up in stages.
wait_for_port() {
    local port="$1"
    local tries=10
    while [ "$tries" -gt 0 ]; do
        ss -tuln | awk '{print $5}' | grep -qE ":${port}\$" && return 0
        sleep 1
        tries=$((tries - 1))
    done
    return 1
}

for port in 53 88 389 445 636; do
    wait_for_port "$port"
    check "port $port is listening" $?
done

# 4. Directory database integrity.
samba-tool dbcheck >/tmp/health-check-dbcheck.out 2>&1
check "samba-tool dbcheck (0 database errors)" $?

# 5. Internal DNS — the node must resolve its own domain.
getent hosts core-node.coop.internal >/dev/null 2>&1
check "internal DNS resolves core-node.coop.internal" $?

# 6. External DNS — confirms the forwarder chain to upstream DNS works.
getent hosts google.com >/dev/null 2>&1
check "external DNS resolves via forwarder" $?

# 7. Ad/tracker filtering path — Blocky must be up AND Samba must actually
#    forward to it. Query a known-blocked domain THROUGH Samba (@127.0.0.1
#    hits Samba's :53, which forwards to Blocky).
#    Expect the block answer 0.0.0.0. Retried with backoff for the same
#    staged-startup reason as check 3. Fail-open is BY DESIGN: if Blocky is down,
#    Samba falls back to upstream and the domain resolves to a real IP —
#    DNS still works but filtering is OFF, which this check surfaces.
systemctl is-active --quiet blocky
check "blocky is active" $?

filter_ok=1
for _ in $(seq 1 10); do
    ans=$(dig +short +time=2 +tries=1 @127.0.0.1 doubleclick.net A 2>/dev/null | head -1)
    [ "$ans" = "0.0.0.0" ] && { filter_ok=0; break; }
    sleep 1
done
check "DNS ad-filtering active (doubleclick.net -> 0.0.0.0 via Samba->Blocky)" "$filter_ok"

# 8. Disk space sanity on both the live-data and backup disks.
for mount in /srv /var/backups/samba; do
    usage=$(df --output=pcent "$mount" 2>/dev/null | tail -1 | tr -dc '0-9')
    if [ -z "$usage" ]; then
        check "$mount is mounted" 1
    else
        check "$mount disk usage under 90% (currently ${usage}%)" $([ "$usage" -lt 90 ] && echo 0 || echo 1)
    fi
done

# 9. Firewall active.
ufw status | grep -q "Status: active"
check "ufw is active" $?

# 10. Coop Library content & knowledge utility active and healthy.
systemctl is-active --quiet coop-library
check "coop-library is active" $?

curl -s --connect-timeout 2 http://127.0.0.1:9095/library/api/health | grep -q '"ok":true'
check "coop-library health endpoint reports ok" $?

# 11. Coop Media sovereign content server active and healthy.
systemctl is-active --quiet coop-media
check "coop-media is active" $?

curl -s --connect-timeout 2 http://127.0.0.1:9096/media/api/health | grep -q '"status":"ok"'
check "coop-media health endpoint reports ok" $?

echo ""
echo "Summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
