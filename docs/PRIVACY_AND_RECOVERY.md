# Privacy and recovery contract

This is an engineering specification and operator guide, not the final public privacy policy. Keep progress and verification evidence in `STATUS.md`.

## Decisions before a real-child pilot

The founder selected the USA and whole-family account deletion, but has not selected a verifiable parental-consent method or retention periods. The founder directed that the workflow be prepared while the real-child pilot remains unavailable. The backend reports `pilot_enabled: false`, `consent_status: not_configured` and `retention_status: not_configured`; there is no parent-facing pilot-enable or consent-verification checkbox. Adult-created fictional development testing continues. These flags do not detect whether a person uploads real child information.

Before pilot collection, record the verification method, notice/version, minimum server-verified receipt, withdrawal process, operator identity/contact and approved retention/deletion timeframes. Parent sign-in, reauthentication and child approval codes do not establish verified guardian consent. Do not accept user-editable Auth metadata as evidence. Follow the current [FTC guidance](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions) and the amended [retention rule](https://www.ecfr.gov/current/title-16/chapter-I/subchapter-C/part-312/section-312.10), with a reviewed policy before implementation. The policy must address collection purposes and deletion timeframes, rather than assuming indefinite retention until a parent requests deletion.

Decide separately for saved content/inactive accounts, device drafts, technical authorization records, operational logs, operator backups and provider records. No new automatic deletion period for creative work is inferred from a session's duration. Existing technical token expiry/cleanup remains distinct from an approved child-data retention policy.

## Parent controls

Parent sign-in → unlock settings → Privacy and recovery.

- Pause all child access holds the family lock, ends all current child sessions and expires unused codes. New approvals/redemptions are denied, including for profiles added while paused. Parent review, saved work and backups remain available. Open child interfaces observe revocation on their existing status checks; received files/screenshots cannot be recalled.
- Allow new parent approvals does not revive sessions, old codes or individually blocked profiles. Each new child sign-in still needs fresh approval.
- Clear device working drafts requires confirmation and removes ImagineOS drafts on the current browser, fencing queued writes. Cloud work, downloaded files, other-device copies and content held in other open tabs have separate limits.
- Permanent family deletion remains the explicit password-confirmed Delete my account flow. Files go through Storage deletion before Auth is removed; family privacy settings cascade with the family.

## Portable saved-content backup

An unlocked parent can download one JSON file containing creator nicknames, all ready original versions and their exact image bytes, organized stories and standalone page drafts. The manifest is checked again after downloads; concurrent content changes fail the backup instead of delivering an inconsistent copy. Original file size, MIME and SHA-256 are verified. The archive also has a canonical-content SHA-256 to detect corruption. A checksum is not proof that an untrusted file was signed by ImagineOS; imported data is validated independently.

Passwords, parent/child sessions, provider credentials, approvals, permission settings, unfinished uploads and unsaved device drafts are excluded. The file is not encrypted. The parent explicitly requests the download and must protect/remove their own copy. No external backup service or paid resource is introduced.

Limits are 100 creator profiles, 250 saved originals, 200 organized stories, 500 page drafts, 32 MiB of image bytes, a 3 MiB server manifest and a 48 MiB archive. Oversized or incomplete content fails as a whole; nothing is silently truncated. Larger-family exports require an administrator procedure before claiming full backup coverage.

## Recovery into the same existing family

1. Sign in to the owning parent account and unlock settings. Choose Review backup and select the downloaded file.
2. Wait for format, digest, image decoding, bounds and reference checks. Selecting an invalid/replacement file cannot leave a previous archive selected for accidental recovery.
3. Choose the creator in the backup and an existing destination creator in that same family. Confirm Recover copies. If artwork was already deleted before backup, the confirmation states the number of affected panels and explicitly includes recovery of their words/order with unavailable-artwork placeholders. Nothing imports merely by opening a file or cancelling.
4. Review the resulting copies in Family creations. Original image bytes, version grouping, story words/order/layout and page words remain exact. Recovered copies have new identities/version references; gaps in historical version numbering need not be reproduced. Existing work is never replaced.
5. If interrupted, retain the file, unlock again and repeat the same file/destination. Stable retry IDs resume completed saves without duplicating content. A story edited after recovery is not overwritten, and a deliberately deleted recovered upload cannot be resurrected by replaying its old retry ID.

Recovery is incremental, not one atomic transaction. Confirmed copies can remain after a later failure. It does not recreate deleted Auth accounts/profiles, restore provider access/permissions, import another family's file, or roll back the database. An unavailable drawing is never recreated, linked to a different version or silently dropped with its story. Explicitly confirmed recovery keeps its exact scene/dialogue/narration, character label, historical version number, format and panel order. New opaque reference IDs remain unavailable and cannot resolve into another stored image. Available drawings retain the normal verified-copy path.

The service-only `recover_story_copy` RPC requires a current verified parent session and unexpired parent-unlock grant, validates the destination child/family and all present references, and atomically creates one story. Identical retries return the existing revision; changed copies and deleted-story tombstones cannot be overwritten or revived. Ordinary child entry and direct authenticated/anonymous RPC calls cannot perform recovery. Normal edits to the recovered story preserve missing references. These guarantees do not restore missing image bytes.

A story with known unavailable artwork can be downloaded only after a separate explicit confirmation to include labelled placeholders. Every panel and exact word remains in order, and scene notes still require their existing opt-in. A failed download/checksum of supposedly available artwork remains an error; the app must not silently turn a transient failure into a placeholder.

## Operator recovery and release checks

The family archive is not a whole-project backup. Supabase [database backups exclude Storage object bytes](https://supabase.com/docs/guides/platform/backups); SQL metadata alone cannot recover deleted drawings. An operator plan must pair schema/data and private object backups with checksums, an approved protected destination, documented retention/expiry, restricted credentials, and an isolated restore rehearsal. Do not erase or restore the development project in place: it contains an existing family's work. Do not provision a new project, backup service or paid plan without authorization.

For a rehearsal, use only the dedicated development target and generated adult `@example.invalid` fixtures. Prepare the Auth fixtures and original-upload fixture described in `backend/README.md`, then run `privacy_recovery_smoke.mjs`. Serve the configured release and run `privacy_recovery_browser.cjs` to exercise a real file download/reopen/recovery and retry. Use Storage-first family deletion for fixture cleanup, verify zero fixture files and authorization/privacy records, then remove ignored fixture JSON. Keep Supabase configuration. Ordinary checks never enable generation or contact a paid provider.

Test interrupted/lost responses, changed/foreign/corrupt files, exact text, old-version references, parent lock/session expiry, family pause/reapproval and later edits/deletion. Keep app error responses generic with trace IDs and never log raw archive contents, drawings, story text, credentials or approval codes. Platform logs and their retention remain part of the separate operational policy. Physical-device and hosted-release checks remain separate from emulated browser tests.
