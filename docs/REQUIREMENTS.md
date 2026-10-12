# Implementation requirements

This is the compact engineering contract extracted from the Founder Bible. It preserves the existing MVP scope. The full source writings remain authoritative and preserved separately; source paths are in `PROVENANCE.md`. Escalate conflicts rather than inventing requirements.

## Product guarantees

- The child draws, names, directs scenes, writes dialogue, and decides the story. AI assists illustration, coloring, layout, and production.
- AI never invents or rewrites child dialogue. Render exact stored text in the app/export, separately from generated illustration pixels.
- Preserve the original drawing as the primary reference. A character must stay recognizable across scenes and sessions; intentional changes create explicit versions.
- Old stories/pages retain their version and asset references. Updating a character must not rewrite prior work.
- Failure must preserve drafts and offer understandable recovery. Do not present an unvalidated illustration as an accepted page.
- Child-friendly controls, readable labels, usable touch targets, predictable navigation, scrolling/reflow, zoom, and keyboard access belong in each affected flow.

## Complete MVP flow

Parent-managed access → child draws in-app or uploads paper artwork → names and saves the character → closes/reopens it → directs a scene and supplies exact dialogue → AI illustrates with validated recognition → saves/reopens the story → exports a useful artifact → parent can manage privacy and deletion.

Both paper upload and a simple in-app drawing flow remain in scope. Upload-first is implementation sequencing. Basic parent explanation alone is not protected parent mode.

## Data and access

- Supabase Auth with explicit parent/child/family relationships. Minimize child data; do not require child email merely to identify a creator profile.
- Persist characters, versions, source/reference/generated assets, stories/pages, exports, and traceable AI jobs as their stages arrive.
- Use private Storage, server-enforced family ownership, RLS, and tests for unauthorized and cross-family access, including linked resource reassignment.
- Keep service-role/secret/provider credentials server-side. Publishable client configuration is public, even if supplied through build variables.
- Test failed/interrupted saves, upload cleanup, reload, version preservation, token/session handling, and deletion/retention before pilot use.

## AI and operating limits

Use an ImagineOS-owned server gateway, initially disabled. Before live generation: validate inputs/outputs, enforce moderation and recognition checks, bounded retries, idempotency, atomic cost reservation/settlement, per-family quotas, trace IDs, and a kill switch. Include failed/retried attempts in accepted-page cost measurements. Stop at exhausted limits without buying credits or discarding drafts.

No live image provider is selected yet. Use varied adult-created fictional drawings for benchmarks. Character recognition, latency, retry ceilings, and acceptable drift need recorded evidence and founder decisions before a pilot.

## MVP exclusions and release gate

No public posting/social feed, multiplayer collaboration, advanced animation, professional drawing suite, or complex classroom features. Books, richer worlds, family sharing, and enhanced print products follow only after the core flow is proven.

Resolve launch jurisdiction, applicable child-data requirements, consent, deletion/retention, safe-output handling, support, recovery, deployment terms, and unit economics before real family use. A technical build or parent-managed pilot does not establish launch readiness.

## Budget

Total ceiling $1,000: coding tools $150 combined; AI benchmarks/pilot $200; hosting/backend/email $125; domain $25; testing/operations $100; contingency $400. These are allocations, not spending authorization. Verify current vendor terms before purchases.
