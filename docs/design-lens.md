# Design Lens — Both Chairs

A way to weigh a design, architecture, or tooling choice by the friction it
creates on *both* sides of it. Adapted from a generic "two sides of the IT
desk" framework into this cooperative's terms.

This is subordinate to [rebuild-brief.md](rebuild-brief.md) — where the two
disagree, the brief wins. It is not a principles doc that competes with the
brief and not a structural doc (rule 2 bans taxonomies; this file names no
departments, services, or module boundaries). It is a thinking aid for a
single kind of question: *when a choice makes one party's life easier and
another's harder, is that trade the right one?*

It sits alongside two things that already exist:

- the **`coop-lens`** steward reasoning frame (a Claude skill, not a file in
  this repo), which weighs **member cost against member benefit**. This lens
  adds the half that frame under-weights: the **steward's own recurring toil**
  as a first-class cost, not an afterthought line item.
- [patterns.md](patterns.md) — where "solve the category, not the incident"
  actually gets practised, by catching a repeat before the third time.

---

## The two chairs

Every choice lands on a **member** (who is also an owner) and on a **steward
or technician** (who has to keep the thing running). The two sides mirror each
other — the same friction seen from opposite chairs:

| Member's chair | Steward's chair |
|---|---|
| Fast, low-friction access | The right access and tooling to help |
| It's reliable and quick | Fewer distinct things to keep working |
| Little effort to use | One clear way a request comes in |
| Fast, human help | An interrupt load a person can actually carry |
| It behaves consistently | It's written down |
| Fixed before it breaks | Clear scope and ownership |
| Told plainly what's happening | Backing to say "I don't know yet" |

Both columns say the same thing from opposite chairs: **remove the friction
between a person and the outcome they want.**

- For the **member**, friction is what they have to *do*, *wait for*, or
  *worry about*.
- For the **steward**, friction is what they have to *chase*,
  *re-figure-out*, or *fight against*.

## The tension, and why it usually resolves

The two chairs trade off in the short term and almost always align in the long
term. A self-service password reset is more work for a steward to build, but
it removes a whole category of requests. A boring, uniform node config annoys
the one member who wanted something bespoke, but it keeps the node
supportable by whoever is on call at 2am.

Cheap-for-now choices shove the cost onto whichever chair wasn't in the room
when the decision got made. In a cooperative that room is small and the same
people rotate through both chairs, so a cost dumped on "the steward" today is
a cost the membership carries next month.

## How to weigh a choice

### 1. Ask both chairs, every time
- What does this cost the member **using** it?
- What does this cost the steward **maintaining** it?

Smooth for one and miserable for the other isn't optimal — it's deferred pain
with a name on it. This is the two-chair extension of `coop-lens` step 2
(member cost): count the steward's hours as real cost too.

### 2. Weight recurring cost over one-time cost
A smooth experience is mostly the absence of *repeated* friction — the daily
login, the weekly request, the monthly firefight. Favour the option with the
lower steady-state cost even when it's the harder build. Every row in the
table above is a place where friction repeats.

### 3. Reduce the number of distinct things — but never by declaring structure
Fewer distinct configs, images, procedures, and ways-in is consistency for
members and supportability for stewards at once. When in doubt, collapse
variety: it's a cost paid forever.

**The rule-2 line, do not cross it:** this means standardising *mechanisms
discovered from working code* — one backup script, one health-check shape, one
way a runbook is written. It does **not** mean pre-declaring the system's
structure: a fixed set of departments, a partition of scope, a module map
written before the code. That upfront partition is exactly what collapsed v0
(rebuild-brief §3). Standardise the how; never enumerate the what in advance.

### 4. Invisible when working, clear when it breaks
Good systems don't announce themselves in normal use and speak plainly at the
moment of failure. Design the failure and edge paths as deliberately as the
happy path — which is just rule 9 (a health signal and one written failure
procedure per module) restated as a design instinct.

### 5. Solve the category, not the incident
"Fixed before it breaks" (member chair) and "an interrupt load a person can
carry" (steward chair) are one instruction: architect so a whole *class* of
problem stops happening, not so each instance gets handled faster. Every fix
asks "how do I make this the last time?" — and when a fix generalises, it goes
in [patterns.md](patterns.md), which is this principle's home.

### 6. Put the cost where it's cheapest to bear — on purpose
Someone always absorbs the friction. Decide *deliberately* that it's the party
best equipped for it — usually shifting effort onto the build phase and off the
daily-use and daily-support phases. And remember the node is finite (rule 8):
"cheapest to bear" is bounded by one mini PC, not by an imagined larger fleet.

## The one-line test

Run any design decision through this:

> **Does this reduce the total recurring friction across both the member using
> it and the steward keeping it running — and if it adds friction somewhere,
> did I choose that spot on purpose?**

---

## The Dumb Terminal, Smart Server Lens (The Sun Ray Model)

To keep both chairs light over time, the cooperative architecture follows the
classic **Sun Microsystems / Sun Ray** philosophy: **"Smart Server, Stateless Edge."**

The server (`core-node`) is the center of gravity; client devices (laptops,
phones, tablets, old PCs) are thin, interchangeable presentation surfaces.

### The 5-Point "Sun Ray" Decision Filter
Before introducing any new tool, UI screen, or workflow, measure it against these
five criteria:

1. **The "Dropped in the River" Test (Edge Ephemerality):**  
   If a member's laptop or phone falls into a river right now, is any unique work,
   state, or unsynced data lost?  
   *Target:* No. All files, session state, and databases reside on the server with
   automated restic snapshots. The member can pick up any other machine on the
   LAN and resume immediately.
2. **The "Zero-Toil Edge" Test (No Client Admin):**  
   Does a member have to install proprietary sync daemons, configure runtimes
   (Node, Python), manage local storage, or resolve client-side file sync
   conflicts?  
   *Target:* No. The service runs in standard web browsers (HTML5 + htmx) or
   through native OS-level network protocols (SMB, CalDAV, WebDAV).
3. **The "Presentation Surface Only" Test (Server-Side Rendering):**  
   Is the client running heavy Single Page Applications (SPAs) burning battery
   and CPU on client-side sorting, filtering, and template rendering?  
   *Target:* No. Per ADR 0004, the server computes, queries, and renders
   semantic HTML/CSS fragments. The browser is purely an output terminal.
4. **The "Compute Density" Test (Work Where the Data Lives):**  
   Where does heavy compute (search indexing, image thumbnailing, media
   transcoding, EXIF parsing) take place?  
   *Target:* On the server. Never transfer multi-gigabyte raw files to client
   devices just to render thumbnails or extract metadata.
5. **The "Strict Server-Side Trust & DAC Boundary" Test:**  
   Does the edge receive unvetted data and hide it client-side with CSS or
   JavaScript?  
   *Target:* Never. The server kernel (POSIX DAC `0700`) and daemon authorize
   every byte before transmission. The edge only ever receives what the
   authenticated identity is permitted to see.

