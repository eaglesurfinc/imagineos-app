# Current implementation status

Updated: 2026-10-15 (America/Chicago). `BUILD_PLAN.md` defines acceptance gates.

## Current increment

Manual cropping/editing of saved uploads is now implemented as a bounded Stage 4 increment. Open a saved character, select its source version, choose Crop and edit, apply a crop/rotation/flip, then Use edited drawing and Save new version. Undo/reset never replace the saved source. Cancel makes no save; failed saves keep the edited bytes and retry identity.

Character details, editor controls, and pure image transformations now live in separate modules under `lib/features/library/`. The library returns to the creation form after accepting edits and blocks opening another character while an unsaved selection is present. Existing offline screens remain necessary for unconfigured startup; no dependencies or backend resources were removed.

Stage 3's original-character loop is implemented and verified on the hosted development backend and local release browser. Stages 0-3 now have evidence. Sign in under For parents, add/select a creator nickname in My characters, choose an original image, name/save it, and reopen it. Intentional updates create numbered versions; earlier names, files and references remain unchanged.

Unfinished uploads remain visible after reopening: finish a stored file, choose the same file again to resume its existing reservation, or discard the pending object and cancel its metadata. Failed saves retain their selected bytes and retry key. Account changes close open originals and clear in-memory drafts/images. The parent panel refreshes its creator count when revisited.

Blank-canvas in-app drawing, AI, stories, export, protected parent locks, consent/deletion, and pilot readiness remain pending. Only fictional adult-created content is authorized during development.

## Verification

- Current editing checks: `scripts/check.ps1` passed dependency resolution, formatting, static analysis, all 29 tests, and release web compilation. New tests verify crop pixels/dimensions/transparency, unchanged source bytes, composed rotation/flip, undo/reset, invalid crop rejection, cancel without a save, stable character identity and identical retry drafts, editor closure on sign-out, keyboard edge adjustment, and cropping/reset at 390 x 844 with 2x text. The browser test runner encountered initialization exceptions and was stopped; it is not counted as a pass. A separate release preview in isolated headless Edge passed pointer and keyboard cropping from an 8 x 8 fictional PNG to a 4 x 8 result, rotate, undo, flip, reset, and the edited PNG handoff. Phone screenshots were inspected; no uncaught runtime exceptions. Full tablet, browser zoom, supported-format, and interruption coverage remains Stage 4 work.
- The Stage 3 baseline check passed formatting, analysis, all 24 tests and release web compilation. The configured release also built successfully. Browser compatibility fixes are covered by explicit regressions for oversized headers and Storage's binary-download missing-object wrapper.
- Prior Stage 3 real Auth/REST/Storage smoke checks passed: concurrent retry idempotency, original-byte save/download, immutable names/files/version references, blocked foreign-family reservation/read/download/sign/upload/finalize/cancel, anonymous denial, and rejection of oversize or mismatched-size inputs. Saved originals cannot be cancelled, even by their owning family.
- Interrupted-upload tests passed: finalize requires an actual matching file; a fresh session can finish a stored pending file; discard removes its object through Storage before cancelling the reservation. Reupload after cancellation is denied. Widget tests verify reselecting the same file after reopening preserves the reserved identity.
- Prior Stage 3 real file-picker browser check passed in isolated headless Edge: select PNG, save, reopen/render, add an intentional new version, reload the app, and reopen/render again. Independent REST/Storage reads confirmed the same character identity with distinct version IDs and both exact byte streams. Phone/tablet screenshots inspected; no uncaught runtime exceptions. The later parent-count refresh is covered by a widget regression; full zoom/keyboard/device-format coverage remains Stage 4 work.
- Hosted SQL test confirmed the composite foreign key rejects a child/family mismatch. Migration history and local files agree: `20261015225320_character_originals`, `20261015231438_character_link_integrity`.
- Temporary test objects were removed through Storage API; SQL confirmed zero remaining fixture objects. Fixture Auth users and cascaded records were deleted; zero remaining fixture accounts. Local credential/fixture JSON files removed and test server stopped.
- Advisor review found no new RLS/security-policy issue. It reports [leaked-password protection disabled](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection); no Auth-plan/settings changes were made. Missing foreign-key covering indexes were fixed; newly created indexes have informational unused-index notices.
- Known nonblocking build warning: Cupertino font family not bundled; Material icons render.

The editing increment adds no schema/policy or SDK changes. Hosted backend/access tests were not repeated for this increment; the live crop-to-Supabase save loop remains to be checked after deployment.

## Hosted targets and prior evidence

Supabase: `imagineos-dev`, ref `hgsivbqmbcliqbstrkdz`, eaglesurf's Org, `us-east-2`, Free at the quoted $0/month creation cost. Public identity is in `backend/project.json`. URL/publishable key remain in ignored local configuration; privileged credentials are absent from Flutter/Git. The `character-originals` bucket is private, capped at 5 MB per PNG/JPEG/WebP object. Image-header limits (16 megapixels) and render/checksum validation run in the client; SQL checks stored MIME/size before publication. This is not server-side content moderation.

Parent account isolation and the original 13-test baseline were verified on 2026-10-12. On 2026-10-15 the founder confirmed live Vercel sign-in and password reset. Hosted origins and email confirmation are founder-confirmed; Auth settings report email enabled and automatic confirmation disabled. Signup email/confirmation delivery remains unverified. No SMTP provider was added.

Vercel build variables are founder-confirmed. Remote deployment tools still lack access to `koletek` (403); the Stage 3 live deployment has not been independently checked. Local CLI login/linking and Docker replay remain unconfigured.

## Next action

After the editing commit deploys, try the live upload/save/reopen/crop/new-version loop using fictional artwork; confirm the initial version still reopens unchanged. Check signup confirmation mail separately with an adult test account; keep email confirmation enabled. No protected parent mode is claimed yet.

Continue Stage 4 with a blank canvas and the minimal in-app brush/color/undo controls, saving drawings through this same original/version pipeline, then complete phone/tablet, enlarged-text/zoom, keyboard and interruption checks. Do not start story generation or live AI before their planned gates.
