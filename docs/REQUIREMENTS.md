# Implementation requirements

This is the compact engineering contract extracted from the Founder Bible. It preserves the existing MVP scope. The full source writings remain authoritative and preserved separately; source paths are in `PROVENANCE.md`. Escalate conflicts rather than inventing requirements.

## Product guarantees

- The child draws, names, directs scenes, writes dialogue, and decides the story. AI assists illustration, coloring, layout, and production.
- AI never invents or rewrites child dialogue. Render exact stored text in the app/export, separately from generated illustration pixels.
- Preserve the original drawing as the primary reference. A character must stay recognizable across scenes and sessions; intentional changes create explicit versions.
- Old stories/pages retain their version and asset references. Updating a character must not rewrite prior work.
- Failure must preserve drafts and offer understandable recovery. Do not present an unvalidated illustration as an accepted page.
- Child-friendly controls, readable labels, usable touch targets, predictable navigation, scrolling/reflow, zoom, and keyboard access belong in each affected flow.

The founder clarified on 2026-10-19 that children need step-by-step organizational guidance while always remaining the creators. Guidance may explain layout, choosing saved characters, entering scene direction/optional words, ordering and reviewing. It must not suggest or fill plots, impose a beginning/middle/end, complete blank fields, correct wording, or add/remove/rewrite story content. Only explicit child actions change content or order. Empty fields and wordless pages are valid choices.

Draw a character once and reuse its selected immutable version throughout a story. A future AI illustration may show that character in the child's directed pose/action and setting (for example, Jon walking down a street), while preserving its recognizable design, drawing style, proportions, colors and distinguishing marks. This is not permission to redesign or substitute a polished character. Original bytes remain unchanged; generated scenes are separate assets. Visual continuity must be validated and the child must review outputs before acceptance; fixed metadata alone does not prove the character was preserved.

Support illustrated pages, comic pages and comic strips as layout choices, without changing drawing style or text. The first original-artwork story flow groups up to 24 ordered pages/panels, uses one chosen character version per panel, saves exact titles/scenes/dialogue/narration, and offers a self-contained printable draft. Comic layouts can group panels but never invent transitions or dialogue. Scene notes appear in print only when explicitly selected. Explicit source deletion leaves these story scenes/words/order intact and marks the drawing unavailable; never substitute another version. This expands draft organization without claiming an accepted generated story or advanced book production.

## Complete MVP flow

Parent-managed access → child draws in-app or uploads paper artwork → names and saves the character → closes/reopens it → directs a scene and supplies exact dialogue → AI illustrates with validated recognition → saves/reopens the story → exports a useful artifact → parent can manage privacy and deletion.

Both photo upload and in-app drawing remain in scope. Upload-first is implementation sequencing. Basic parent explanation alone is not protected parent mode.

The founder requested separate parent sign-in and child entry on 2026-10-20, for both shared family devices and each child's own device. Parents create and manage child profiles and authorize/revoke device access. Children must not receive the parent's password, provider keys or parent session. A creator dropdown is not authentication: child sessions must be restricted server-side to their own profile and permitted operations, including Storage and exported data. Parent-managed permissions must control AI use and spending, export and destructive actions; permissions cannot waive product safety rules or authorize changing a child's story. Specify the initial supported controls and defaults before exposing them. No child email, real name or date of birth is required for this access design.

The first intended pilot is in the USA. On 2026-10-20 the founder confirmed that a parent-confirmed Delete my account request permanently deletes the entire family account: all child profiles, characters, versions, stored files, stories and provider connections, followed by the parent Auth account and sessions. An interrupted request must be resumable without permitting new cloud saves. Explain separately the limits for downloaded copies, other devices and infrastructure/provider retention. Consent verification, retention periods and pilot readiness still require a recorded decision and evidence; parent sign-in alone does not establish legal guardianship or consent.

The founder expanded Stage 4 on 2026-10-19: provide drawing kits, useful colors and utilities, and extract artwork from both paper photos and busy backgrounds onto an empty canvas. Include brushes, adjustable size/opacity, palettes/custom colors, shapes, fill, eyedropper, erasing, undo/redo, and canvas zoom. Extraction must offer review and correction, preserve the uploaded original, and save accepted edits as explicit new versions. Paper cleanup and manual outlined cutouts satisfy the initial extraction workflow; automatic semantic background separation requires a later recorded provider decision and authorization. A full professional art suite remains outside this increment.

The same day's follow-up requires paper cleanup that protects faint drawing lines, more precise connected-area removal, rectangular pointer/lasso selections for targeted edits, additional shapes, and touch/pen input through the current device. Use device-reported pressure and eraser input where available; prioritize pen strokes over finger contact and provide touch navigation plus a pen-only option. Support compatible pens exposed by the operating system without a vendor-specific integration. Bluetooth pairing belongs to device settings; a paired accessory alone does not establish digitizer compatibility. Add Save to device for a PNG copy of the current canvas, including transparency and offline use, without changing the cloud library or saved originals.

The founder's Stage 5 follow-ups on 2026-10-19 include correcting paper extraction that fails on photographed pages, keyboard Delete/Backspace for the active canvas selection with Undo and safe text-field focus, and a canvas text tool with a useful choice of fonts, sizes and changeable colors. Preserve exact typed text, editable device recovery and PNG saving; retain the source drawing and reviewed extraction. Bundle licensed fonts rather than adding a runtime font-service requirement.

## Data and access

- Supabase Auth with explicit parent/child/family relationships. Minimize child data; do not require child email merely to identify a creator profile.
- Persist characters, versions, source/reference/generated assets, stories/pages, exports, and traceable AI jobs as their stages arrive.
- Use private Storage, server-enforced family ownership, RLS, and tests for unauthorized and cross-family access, including linked resource reassignment.
- Keep service-role/secret/provider credentials server-side. Publishable client configuration is public, even if supplied through build variables.
- Test failed/interrupted saves, upload cleanup, reload, version preservation, token/session handling, and deletion/retention before pilot use.
- Allow confirmed deletion of a whole character or one selected version within the owning family. Remove selected files and records, retain other versions, and offer retry after interruption. Use whole-character deletion for the last saved version. Original preservation during edits does not prevent explicit user-requested deletion.

## AI and operating limits

Use an ImagineOS-owned server gateway, initially disabled. Before live generation: validate inputs/outputs, enforce moderation and recognition checks, bounded retries, idempotency, atomic cost reservation/settlement, per-family quotas, trace IDs, and a kill switch. Include failed/retried attempts in accepted-page cost measurements. Stop at exhausted limits without buying credits or discarding drafts.

Support parent-owned OpenAI, Claude and Gemini connections with accurate capability and billing explanations. The founder approved both eligible subscription allowances and API credits on 2026-10-19. Use official provider authentication; subscription access requires an eligible approved integration, and a sign-in alone does not authorize API/image usage. API keys and tokens remain encrypted server-side, isolated by family; connecting/replacing/disconnecting requires parent confirmation. Never silently spend a different account's balance or substitute paid API usage for subscription allowance. Claude currently supports image analysis, not native illustration generation.

No live image adapter is enabled yet. The founder instructed that generation remain disabled until a parent connects an account. Use varied adult-created fictional drawings for benchmarks. Character recognition, latency, retry ceilings, and acceptable drift need recorded evidence and founder decisions before a pilot.

The founder supplied a paper drawing for local extraction debugging and requires the empty page, including shadows and enclosed areas, to become transparent while retaining the original drawn lines. Keep the photo and previews outside public Git and provider requests. Validate actual blank regions and line details; transparent percentage of the entire image is not a paper-removal success score. Preserve the original and offer review/Undo.

## MVP exclusions and release gate

No public posting/social feed, multiplayer collaboration, advanced animation, professional drawing suite, or complex classroom features. Advanced book production, richer worlds, family sharing, and enhanced print products follow only after the core flow is proven. Basic ordered illustrated/comic drafts above are included under the founder's format expansion.

Resolve launch jurisdiction, applicable child-data requirements, consent, deletion/retention, safe-output handling, support, recovery, deployment terms, and unit economics before real family use. A technical build or parent-managed pilot does not establish launch readiness.

## Budget

Total ceiling $1,000: coding tools $150 combined; AI benchmarks/pilot $200; hosting/backend/email $125; domain $25; testing/operations $100; contingency $400. These are allocations, not spending authorization. Verify current vendor terms before purchases.
