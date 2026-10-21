# Verification and operations contract

Implementation/deployment evidence belongs in `STATUS.md`. These procedures do not claim a completed pilot, hosted CI run, monitoring rollout or restore rehearsal.

## Repeatable offline checks

With Flutter/Dart and Node 24+ on PATH, run `./scripts/check.ps1` from PowerShell. It enforces the committed dependency lockfile, checks Dart formatting and static analysis, runs Flutter tests and every `backend/tests/*_test.mjs` file, then builds web. `npm test --prefix backend` runs the same offline Node test set. Hosted smoke/browser/database suites remain explicit separate checks; ordinary tests use no provider credentials or paid calls.

`.github/workflows/check.yml` runs these checks on pull requests, main pushes and manual dispatch. It uses immutable official action revisions, read-only repository permissions and no secrets or deployment credentials. `scripts/flutter-sdk.sh` shares the exact verified Flutter version/revision with the existing Vercel build. A mismatched SDK directory fails instead of silently changing versions. Hosted Actions execution and required branch-protection checks need their own evidence after publication; the workflow does not publish or deploy anything.

After building, `node backend/scripts/release_manifest.mjs` prints a fingerprint of every web output file, the checked-out source commit and whether the working tree is dirty. CI writes it to `build/release-manifest.json`; local copies belong under ignored `build/`. It does not attest that the files were built from that commit or that tests/deployment succeeded. Record those checks separately. Compare the same artifact hashes during a release/rollback rehearsal; do not label a dirty checkout a reviewed release.

## Request diagnostics without creative content

The shared request logger accepts only a fixed function name, HTTP method/status, allowlisted result code, UUID trace and bounded elapsed time. It emits one JSON event named `imagineos.request`, schema 1. Handled authorization failures, preflights, JSON results and child binary downloads are covered. A broken logging sink must not fail/repeat a user operation. Runtime crashes before handler completion may produce only the platform's own failure record.

Never log request bodies, URLs, headers, passwords, Auth/child session tokens, parent grants, provider secrets, names, family/child IDs, image bytes, scene text, dialogue, narration or raw upstream errors. A trace is for narrow incident correlation; do not use it as a metric label. The application's whitelist does not change Supabase or provider infrastructure logging/retention. Confirm those settings and approved retention before a real-family pilot.

On the approved development project, inspect a narrow function/time range and filter custom events by `imagineos.request`. Supabase documents [function log sources and filtering](https://supabase.com/docs/guides/observability/advanced-log-filtering). Export only the custom JSON event messages into an ignored local file when needed. For example:

```powershell
Get-Content -LiteralPath 'build/request-events.jsonl' | node backend/scripts/summarize_logs.mjs
```

The report contains only function/status/code groups, counts and mean/max latency. It excludes trace IDs and never echoes rejected input. Check `ignored` before trusting a report: platform export envelopes must be converted to event-message JSON lines first. Do not commit raw exports or private incident data. No automatic paging, external log collector or retention policy is implicitly configured. Before pilot use, assign an incident owner and approve alert thresholds for sustained 5xx, latency, denied access, stalled jobs and storage/service capacity.

`backend/tests/service_storage_checks.sql` is an operator-only, read-only snapshot of database/file sizes, pending uploads, missing/untracked file counts and unsettled jobs. It contains no names, identities, file paths or creative content and changes no limits or data. Run it on the approved target before/after rehearsals and compare with that project's current dashboard limits. A missing ready file or untracked file requires investigation; do not delete it automatically. The counters do not measure bandwidth, email deliverability, billing or all provider limits.

## Paired operator-backup verifier

`node backend/scripts/verify_backup.mjs <private-staging-directory>` hashes a prepared, local backup bundle without connecting to a service, executing SQL, copying/uploading files or restoring data. It returns counts/bytes and a manifest digest only. File corruption, missing/extra files, unexpected targets, duplicate objects, traversal, links and unbounded input are rejected. This is integrity checking of supplied files, not proof of source completeness, a consistent database snapshot, decryption/Vault recovery or successful restore.

The staging directory contains `operator-backup.json`, `database/roles.sql`, `database/schema.sql`, `database/data.sql`, and object bytes at `objects/character-originals/<family-uuid>/<asset-uuid>`. The JSON schema is:

```json
{
  "format": "imagineos-operator-backup",
  "version": 1,
  "source_project": "hgsivbqmbcliqbstrkdz",
  "captured_at": "2026-10-20T00:00:00Z",
  "snapshot_label": "operator-chosen-capture-label",
  "database": {
    "roles": {"path": "database/roles.sql", "bytes": 1, "sha256": "<actual hex digest>"},
    "schema": {"path": "database/schema.sql", "bytes": 1, "sha256": "<actual hex digest>"},
    "data": {"path": "database/data.sql", "bytes": 1, "sha256": "<actual hex digest>"}
  },
  "storage": []
}
```

Replace byte lengths/digests with actual values. Each storage entry has `bucket: "character-originals"`, `object_path: "<family-uuid>/<asset-uuid>"`, `path: "objects/character-originals/<family-uuid>/<asset-uuid>"`, `bytes` and `sha256`. An empty list is valid only for a source that actually has no objects; verify against the captured source inventory. Bounds: 50,000 objects, 16 MiB manifest, 2 GiB per file. Existing source uploads keep their normal smaller app limit. The manifest is unsigned and private: a digest detects accidental corruption, not a maliciously rewritten backup.

No real family export is captured by these tools. Before actual operator capture, approve a protected destination/access policy, encryption and key recovery, expiry/deletion handling, a consistent capture/write-pause procedure, and an isolated disposable restore target. Database dumps include private data and must never enter public Git. Pair database metadata with all private object bytes; review Auth, extensions, roles, Vault/key recovery, Auth URLs and Edge Function configuration separately. The official [CLI backup/restore guide](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore) currently uses Docker for CLI dumps. Docker remains declined here; do not install it or invent a completed alternative capture/rehearsal. A separately approved compatible Postgres-tool workflow can be evaluated when a target is selected.

## Spending and uncertain failures

Keep global generation disabled and operator/family authorizations at zero until the approved benchmark. The existing private ledger atomically reserves against both caps and daily attempts, permits one dispatch claim, and rejects changed-payload replays. A provider key connection does not enable these controls. OpenAI project spend limits add a separate provider-side safeguard; they do not replace reservations.

Before wiring the image transport, verify current model eligibility, worst-case reservation and reported usage against actual billing. Reserve/claim before a request and settle every outcome. An unknown charge retains its reservation; neither a timeout, malformed output, moderation refusal nor a failed save is evidence of zero provider cost. A returned candidate remains private/unaccepted until complete decoding, moderation, character recognition and child review pass. Never retry through another account/provider or buy credits automatically.

## Release and rollback

Record the reviewed source commit, offline checks, hosted smoke results, configuration names, function versions/JWT settings and target before release. Never put credential values in the record. Use only the existing approved development project; preserve its existing family data. Child access intentionally validates its opaque capability with platform JWT verification disabled, while parent/provider functions retain platform JWT verification.

For a code-only rollback, restore the prior reviewed source/function bundle and deployment configuration on that same target, then repeat authentication, isolation, disabled-generation and save/reopen checks with fictional fixtures. Keep generation disabled throughout. Git reverting application code does not undo a database migration or restore Storage. Database/file backup destinations, expiry and a whole-project isolated restore rehearsal remain separate decisions under `PRIVACY_AND_RECOVERY.md` and the build plan. Do not erase data, create a new environment or claim a restore was verified merely because a web deployment rolled back.
