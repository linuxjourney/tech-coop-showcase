# Tech Coop — Rebuild Brief

Instructions for Claude Code. Supersedes any earlier principles or architecture
doc in this project.

**Task:** archive the existing tech coop repository, salvage a short list of
artifacts from it, wipe it, and start a new repository under the operating rules
in section 5.

**Before starting:** confirm the repository name and remote URL with the author.
Do not infer it. Do not operate on any repository not explicitly named.

---

## 1. What was explored

A technology cooperative platform, intended to prove out on homelab hardware and
later serve a pilot city. Built as a pnpm + Turborepo monorepo with a Hono API,
a Vite/React portal, Authentik for OIDC/SSO, and Docker Compose. The platform
shell was completed. The organizational model was defined up front as eleven IT
departments, each with an RBAC scope, an MVP contract, and explicit out-of-scope
boundaries, with decisions recorded in ADRs.

## 2. What worked

- **The homelab-first instinct.** Proving on owned hardware before public
  infrastructure was correct.
- **ADRs as a habit.** The practice was right; the volume was not.
- **Authentik for OIDC/SSO** and **Docker Compose with named volumes** both
  reached a working state. Working is not the same as chosen — the author has
  not committed to either for v2. Treat them as candidates, not carry-overs.
  See section 6.

## 3. What didn't

- **The eleven-department partition.** Roughly thirty interlocking definitions
  written before a single real user existed. Because the departments were
  defined as a partition of a whole, no boundary could move without
  renegotiating its neighbors, which invalidated ADRs and the module map. This
  is the root cause of the collapse.
- **Documentation weight applied uniformly.** Reversible choices got the same
  ceremony as irreversible ones, so ordinary changes carried paperwork cost.
- **Governance fused to software.** An unresolved question — whether the pilot
  city would be a legal member cooperative from day one — sat upstream of
  technical decisions it should not have touched.
- **Scale phasing tied to product scope.** Homelab → pilot city meant "what does
  this do" and "where does it run" moved together, so adding a module raised
  DNS and certificate questions.
- **No first user.** Nothing was ever validated against a real person's need.

---

## 4. Execution

### Phase A — Archive (do this first, verify before continuing)

1. Confirm the working tree is clean and everything is pushed.
2. Tag the final state: `git tag -a v0-final -m "final state before rebuild"`
   and push tags.
3. On the remote, rename the repository to `<name>-v0-archive` and mark it
   archived. Do not delete it.
4. Keep a local clone at a path outside the new working directory.
5. **Verify the archive is reachable before proceeding.** If verification fails,
   stop and report.

### Phase B — Quarantine

Copy out of the archive into a holding directory **outside the new repository**.
Nothing here enters the new repository until the author decides it should. The
purpose of this phase is to avoid re-deriving fiddly configuration later, not to
commit to any of it.

- `authentik/` blueprints, OIDC client config, redirect URIs, related env keys.
- `docker-compose*.yml` and volume definitions.
- A single flattened file, `rejected-options.md`, containing only the
  alternatives that were tried and rejected and the reason each failed. Extract
  this from the old ADRs. Discard the decisions themselves — they are void.
- Environment facts: hardware roles, port counts, what is physically wired to
  what.

**Do not carry forward at all:** department definitions, RBAC scope tables, the
module map, MVP contracts, out-of-scope boundaries, or the phasing plan. Pulling
any of these into the new repository will recreate the partition.

Strip secrets from everything before it leaves the archive.

### Phase C — Wipe

Destructive and irreversible. **Ask the author to confirm Phase A verification
passed before running anything here, and let the author perform the remote
deletion themselves.**

- Local: remove the old working directory only after the archive clone is
  confirmed present elsewhere.
- Remote: the archived repository stays. Nothing is force-pushed over existing
  history.

### Phase D — Refresh

Create a new repository with a fresh `git init` and no imported history.

Initial contents, in this order:

1. This file, at `docs/rebuild-brief.md`.
2. `CLAUDE.md` — one line pointing at it.
3. `docs/rejected-options.md`.
4. Nothing else. Do not import anything from quarantine. Do not scaffold a
   monorepo, a portal, a service layer, or an identity provider until the
   questions in section 6 are answered.

---

## 5. Operating rules

1. **Modules hide decisions.** A module is defined by the change it absorbs, not
   the function it performs. If that sentence can't be written for a proposed
   module, it isn't one yet. Modules are discovered from working code, never
   declared in advance.
2. **No taxonomies.** Never enumerate departments, services, or modules ahead of
   the code. Never define a set of boundaries as a partition of a whole. Names
   are labels applied afterward and renaming must cost nothing.
3. **One uniform interface between modules,** chosen once and used without
   exception. No reach-through into internals, no shared mutable state as an
   integration path. Not yet chosen — see section 6.
4. **Two change lanes, sorted by reversibility.** Reversible in minutes: ships
   continuously, no ADR, no ceremony. Expensive to reverse — schema, identity
   provider, tenancy, member data, public interfaces: written decision first.
5. **Runbook before automation.** Write the procedure a human could follow at
   2am, then script it. An action with no written procedure is unsupported.
6. **Append-only operations log.** What happened, who did it, why. Same
   substrate as incident history and audit trail. Never rewritten.
7. **Reconcile, don't react.** Prefer a loop comparing desired to actual state
   over event chains. Event-driven designs need a requirement to justify them.
8. **Capacity is an input.** Single node: mini PC, 8th gen i5 vPro, 32 GB RAM.
   A design that doesn't fit is rejected, not deferred. Distribution requires
   arithmetic showing one node won't hold — show the arithmetic.
9. **Definition of done, per module:** install command, backup, restore verified
   by actually restoring, health signal, one written failure procedure.
10. **ADRs only for irreversible decisions.** One per decision, not per module.
    Record the decision, the rejected alternatives, and why. No document may
    enumerate the system's structure.
11. **Governance never blocks software.** Legal and organizational questions run
    on their own track.

---

## 6. Stop and ask

Do not invent answers to these.

- **The first transaction.** What is the first concrete thing this system does
  for a real person who is not the author? Not the first module — the first
  actual exchange of value. Phase D stops here until this is answered.
- **The stack.** Whether v2 reuses the v1 codebase, language, or framework
  choices at all is open. Nothing in v1's implementation is presumed forward.
- **The identity provider.** Authentik worked in v1 but is not chosen for v2.
  This is a slow-lane decision under rule 4 and needs a written one.
- **The uniform interface** (rule 3) — pending ADR 0001, to be decided before a
  second module exists.
- **Where backups physically land.**
- **Whether the deployment target supports DHCP reservations,** which determines
  whether stable service URLs can be assumed.
