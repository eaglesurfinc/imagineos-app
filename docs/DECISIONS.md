# Implementation decisions

Record a dated decision, reason, consequences, and verification here when a material choice changes. Unresolved product questions stay visible; examples in older decision templates are not proof of approval.

## 2026-10-11 — One build repository, separate product writings

Founder requested a new public repository and a lean execution path. Flutter source lives at this repository's root; backend CLI, Supabase configuration, future migrations/functions/tests live under `backend/`. Compact requirements, build plan, status, and decisions are the daily engineering entry points. The full Founder Bible stays separate and preserved. Existing mobile/backend repositories remain historical sources; new feature work belongs here after consolidation.

Copy only reviewed current build files into a new history, with source commit IDs and import hashes in `PROVENANCE.md` and `import-manifest.json`. Do not publish the private planning corpus or old Git histories. This preserves original records while preventing historical secrets or internal writings from entering the public repository accidentally.

## 2026-10-11 — Hosted Supabase preparation; creation on hold

Supabase remains the chosen Auth/PostgreSQL/private Storage provider. Prepare Flutter build-time URL/publishable-key configuration, with offline preview supported. Hosted development is intended because Docker installation was declined. The founder selected eaglesurf's Org, then explicitly held project creation after the $0/month quote. No hosted project, schema, or actual connection is claimed until that hold is lifted and verified.

Coding-agent choice is independent of the application AI provider and does not alter the stack or requirements. No illustration provider has been selected. Vercel deployment is deferred; making source public does not make commercial use eligible for Hobby.

## 2026-10-12 ? Resume hosted development and verify the build

The founder authorized Supabase creation, dependency resolution, and full build verification after the earlier hold. Created `imagineos-dev` in the previously selected eaglesurf's Org at the freshly quoted $0/month Free cost. Selected `us-east-2` for the Chicago development environment. Public project identity is in `backend/project.json`; local URL/publishable-key configuration remains ignored.

The client dependency remains pinned to 2.18.2 and the backend CLI to 2.120.0. Both dependency installations and the Flutter checks/releases passed. Auth endpoint and server-side database probes passed; browser startup was checked in offline and configured modes. Data API schema discovery requires a server secret; the client smoke check verifies that restriction instead of obtaining privileged credentials.

Hosted Auth URLs/email settings remain to be reviewed before sign-in implementation. Local template changes are not hosted configuration. Docker and Vercel deployment remain deferred.

## 2026-10-12 - Explicit Vercel Flutter build

The founder reported a root 404 after importing and reimporting the public repository into Vercel. Added a file-based build command and `build/web` output directory instead of relying on framework detection. The Linux build script fetches the official Flutter 3.47.2 tag and verifies revision `d3b14c876900e553bc736ca19295fc09e3853e8e`, matching the validated workstation SDK. The lockfile is enforced. Only generated web output is published; no Flutter source, private planning, backend credentials, or SDK cache belongs in the static output.

Optional build variables supply only the Supabase URL and publishable key; absent configuration keeps the existing offline shell usable. No rewrite is needed for current internal tab navigation. Remote logs/settings remain unavailable because the connected Vercel credentials receive 403 for `koletek`; a confirmed remote root cause or successful deployment is not claimed.

## 2026-10-12 - Parent accounts and family isolation

Use Supabase email/password sign-in with email confirmation and password recovery. Parent authentication controls account access; it does not establish adult identity or implement the later parent-lock/consent features. One parent has one family for this increment. Child profiles have a nickname only: no child email, birthdate, or additional personal details.

Auth owns credentials. `parent_profiles` references `auth.users`; `families.parent_user_id` is unique and immutable to clients; `child_profiles` belongs to a family. A private, non-client-executable Auth insert trigger provisions parent/family rows for nonanonymous email accounts. It needs SECURITY DEFINER to write those rows, uses an empty search path and qualified names, and ignores user metadata. Clients can read their own parent/family context and insert/rename/delete their own child profiles. Column grants deny changing child-family links; RLS checks ownership on every child operation. Administrative family membership, invitation, and child credentials are deferred.

Applied the versioned migration only to the dedicated development project. The CLI-created local migration filename was aligned with the hosted migration history version `20261013014911` after application. SQL and real Auth/Data API tests verified the ownership boundaries. Temporary fictional accounts were removed. Existing JWTs may remain valid until expiry after sign-out/deletion, but deleted family records grant no access; strict session revocation for sensitive operations remains a later parent-controls requirement.

The founder confirmed hosted origins/redirects and email confirmation settings, and later confirmed both Vercel build variables are set. Email-provider confirmation is enabled according to the endpoint. Default hosted email delivery and confirmation/recovery callbacks still require a manual adult test; no SMTP provider or paid delivery service was added.

## 2026-10-15 - Immutable originals and explicit character versions

Stage 3 uses character identity, numbered character versions, and one source asset per version. Names belong to versions; adding an intentionally revised drawing never edits earlier names or files. The server resolves the family from the selected child profile. Clients cannot directly write character/version/asset metadata or reassign its ownership. The read view uses SECURITY INVOKER and underlying RLS.

The private `character-originals` bucket accepts PNG/JPEG/WebP up to 5 MB. The Flutter picker checks file signatures, reads dimensions with a portable header decoder before expanding pixels, verifies renderability, rejects more than 16 megapixels, and preserves original bytes. No resize, AI processing, or original replacement occurs. Client checksum checks verify the bytes on upload recovery and reopening; SQL publication verifies Storage metadata size/type, not a server-computed cryptographic digest. Image headers and metadata are not server-side content moderation or image sanitization; those remain future gateway/privacy work.

Saving has three states: pending, ready, and cancelled. A retry UUID atomically reserves a character/version/path through authenticated invoker RPC wrappers backed by nonexposed, ownership-checking privileged functions. Equal retry keys are serialized and checked against the original parameters. Publication requires a matching stored object and is idempotent. Storage INSERT/DELETE policies lock pending asset rows to serialize against publication; UPDATE/upsert is never granted. Published metadata/files cannot be edited or deleted through client access.

After interruption, the library lists pending uploads: finish an already uploaded image, reselect the same file to reuse its reservation, or discard the pending object through the Storage API before cancelling its metadata. Cancelled metadata is retained for retry/history consistency and hidden from the library. This is user-driven cleanup, not a scheduled global retention job. Original/version removal and account-wide deletion still require the later protected deletion workflow. In-memory drafts and decoded images are cleared when account identity changes.

Pinned `file_selector` 1.1.0, `crypto` 3.0.7, `uuid` 4.6.0, and `image` 4.12.0; the Supabase SDK remains 2.18.2. Hosted migrations are `20261015225320` (originals) and `20261015231438` (covering indexes and a composite child/family foreign key). CLI-generated filenames were aligned with hosted history. Verification uses fictional adult-created images and accounts only. No live illustration provider or additional paid service was introduced.

## 2026-10-15 - Manual edits preserve uploaded originals

The founder requested cropping/editing uploaded characters and a focused code cleanup. Reopen a saved character/version to crop, rotate right, or flip horizontally. Undo/reset affect only the editing session. Using the edited drawing returns a PNG to the existing explicit new-version form; only Save new version publishes it. The initial uploaded bytes and all earlier version references remain unchanged. Editing a previous version uses the same character identity, with the selected name visible for review before saving.

Crop controls use labeled percentage ranges with a visible crop overlay. Explicit keyboard shortcuts move the first edge with left/right arrows and the second with Shift + arrows; the installed Flutter range control did not supply this behavior on its own. Pending crop selections must be applied or cleared before rotation/flip or accepting the drawing. Edits replay a maximum of 20 small commands from the source, avoiding decoded-image undo snapshots; failed transforms retain the previous result. EXIF orientation is baked before transformations, transparency is preserved, and animated inputs produce a still first-frame edit. Edited PNGs retain the existing 5 MB limit. Flutter Web processes commands on its main thread, so large images may take time. Closing/reloading before saving discards session edits; the stored original remains available.

Extracted character details and image transformations into separate modules, removed the embedded detail implementation and unnecessary imports/image copying, and reused the existing immutable upload/retry pipeline. No dependencies, database schema, access policies, or paid services changed. A current file selection must be saved or cleared before opening another character, preventing accidental draft replacement. This bounded editing increment does not complete Stage 4's blank-canvas brush/color drawing gate.

## 2026-10-19 - Explicit character and version deletion

The founder requested whole-character deletion and removal of selected versions. Both require a confirmation identifying the scope and permanent removal. Deleting a version keeps the character and other versions; deleting the last saved version must use Delete character so the user explicitly chooses to remove the identity. Whole deletion also covers pending/cancelled upload reservations. This is authenticated family access with confirmation, not the later protected parent lock or full account/retention workflow.

Deletion uses begin/finish invoker RPCs backed by private ownership-checking functions. The server marks the selected assets as deleting before returning paths. The client removes files through the Storage API in batches of 100; SQL finalization refuses to remove references while any selected Storage object remains. Interrupted operations stay visible and can be resumed after a new session. Foreign/missing IDs produce identical no-ops without exposing foreign paths. Ready assets remain immutable outside an explicitly begun deletion. See [Supabase object deletion](https://supabase.com/docs/guides/storage/management/delete-objects).

Family/character/asset locking serializes deletion against reservations, publication, and Storage writes. Version numbers use an atomic character counter and are never reused after deleting a high version. Private retry tombstones retain only a request UUID, family UUID, and time; they prevent stale initial-upload retries from restoring removed artwork and cascade when the family is deleted. They retain no names, images, or checksums. Retention for these minimal records belongs to Stage 8. New future story/page references must be checked before beginning deletion when those tables are introduced; this increment has no saved stories/pages.

Stored originals remain unchanged during edits; explicit confirmed deletion is the exception authorized here. Already downloaded or cached copies cannot be recalled by deleting server objects. The app clears its decoded-image cache and the tests use fresh URLs plus Storage/SQL checks. Migration `20261019201740_character_deletion` was applied only to the dedicated development project. The founder requested no push to main; implementation stays local on `feature/character-deletion` for review.

## 2026-10-19 - Local drawing studio and reviewed extraction

The founder expanded Stage 4 to drawing kits and extracting artwork from both paper and busy photographs. Use local pixel processing, with paper cleanup, a manually outlined cutout, connected-area removal, and an eraser. Preview extraction before accepting it; sensitivity changes always start from the pre-extraction drawing. Light/pale artwork can be affected by paper cleanup and needs review. This is manual-assisted extraction, not automatic semantic segmentation. No image provider, paid call, server function, or schema change is introduced.

Save an upload unchanged before opening its studio. Work on an EXIF-oriented, first-frame copy capped at 1536 pixels on its longest edge; blank canvases are 1024 square. Accepted studio output is a PNG using the existing 5 MB immutable save/retry/version pipeline. Transparency is real alpha; the checkerboard is only a preview. Background color is separate from paint so erasing reveals the chosen background or transparency. Brushes, pressure-aware strokes, four palette kits, custom colors, line/shapes, fill, eyedropper, opacity, undo/redo, and pan/zoom cover this increment. No automatic redraw or dialogue generation occurs.

Keep editable strokes and the current pixel base in best-effort device recovery; cloud versions are flattened PNG snapshots that can be reopened for pixel editing and additional drawing. Undo is bounded to 40 frames and 20 MB of unique base images; redo is discarded after a new action. Merging paint retains the appearance while freeing stroke capacity. Reload restores the current frame and starts fresh undo history. Completed changes checkpoint after a short debounce; an unfinished pointer stroke or an immediate tab closure can lose the latest change.

Pin `shared_preferences` 2.5.6 (already present transitively) as a direct dependency for device drafts. Each JSON record is capped at 3 MB; quota failures show a recovery warning and keep the explicit cloud-save path available. This follows the package's [best-effort persistence limitation](https://pub.dev/packages/shared_preferences). Namespaced account-scoped keys separate drafts from Auth storage. Account changes fence queued writes immediately, close private screens, and clear drawing drafts; browser verification must check sign-out cleanup. Successful cloud saves and confirmed character/version deletion remove their matching device drafts. Local storage is not encrypted or a backup and does not complete Stage 8 retention/parent controls.

Stage 4 work is local on `feature/stage-4-drawing-studio`, including the preceding deletion commit. The founder's no-push hold remains active. No Vercel deployment is authorized by this increment.

The founder also requested a brighter child-friendly application and code cleanup. Centralize the sunny yellow, teal, coral and light-blue Material theme in `lib/theme.dart`; keep dark readable labels and a quiet canvas. Drawing models, rendering, pixel operations, tool/color controls, extraction review and device recovery have separate modules. Shared studio navigation removes duplicate route construction, and a typed operation enum replaces string-based processing branches. Keep existing offline, crop and upload-recovery paths because they still serve distinct user flows.

## Decisions needed in their stages

- Stage 6: illustration provider, recognition/drift thresholds, retry limits, benchmark authorization.
- Stage 7: default export format.
- Stages 8–9: parent controls/consent details, retention/deletion, launch jurisdiction and distribution readiness.
