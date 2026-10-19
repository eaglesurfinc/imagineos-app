# Illustration contract v1 (disabled)

Stage 5 is a page-planning foundation. No illustration provider, provider credential, generated image, cloud story or billable operation exists in v1. Enabling generation requires reviewed code and the Stage 6 controls; an environment flag cannot enable this handler.

## Request and access

POST `/functions/v1/illustration-gateway` with the public project API key and signed-in parent's bearer JWT. Platform JWT verification stays enabled. The handler additionally validates the user through Auth and resolves the exact ready original through the caller's RLS-scoped `original_uploads` view. Anonymous accounts, foreign/missing references, changed checksums and deleting versions are rejected. It reads only Auth/Data API, uses no administrative key, and does not download/sign artwork URLs. There is no schema migration.

The canonical [request fixture](../backend/tests/fixtures/illustration_request.json) defines the exact allowed keys:

- `contract_version: 1`, UUID `request_id`, UUID `trace_id`, UUID `page_id`.
- `character`: UUID `character_id`, UUID `version_id`, UUID original `asset_id`, lowercase hex `sha256`.
- `scene_direction`: nonblank exact string, at most 2,000 UTF-16 code units; `layout: "portrait"`.

Additional keys are rejected, including dialogue, narration, family/owner IDs, URLs, model/provider selection and enable flags. The actual UTF-8 body is capped at 16 KiB. Scene whitespace is validated without rewriting. Request/trace IDs belong to one logical check and are reused for its manual transport retry.

Fingerprint = lowercase SHA-256 of UTF-8 JSON encoding of `[1, page_id, character_id, version_id, asset_id, sha256, scene_direction, "portrait"]`, in that order. Page text and correlation IDs are absent. Both languages test the same fixture/hash.

Allowed browser origins: `https://imagineos-app.vercel.app`, `http://localhost:8766`, `http://127.0.0.1:8766`. Authenticated API clients without Origin can also check. Responses are `no-store`; preflight permits the SDK's public headers. Preview deployments need an explicit origin decision.

## Response and failures

A valid authorized check returns HTTP 200 with exactly these fields:

```json
{
  "contract_version": 1,
  "request_id": "<same UUID>",
  "trace_id": "<same UUID>",
  "fingerprint": "<computed SHA-256>",
  "status": "disabled",
  "code": "GENERATION_DISABLED",
  "retryable": false,
  "output": null,
  "cost_micros": 0,
  "provider_attempts": 0
}
```

Trace also appears in `x-trace-id`. Failure envelopes use the same fields: HTTP 401 `AUTH_REQUIRED`, 404 `REFERENCE_UNAVAILABLE`, 422 `INVALID_REQUEST`, 403 `ORIGIN_DENIED`, 405 `METHOD_NOT_ALLOWED`, or 503 `BACKEND_UNAVAILABLE`. Only 503 is retryable. Unparsed requests have null request/fingerprint and a server-generated trace. Platform authentication errors can precede the handler. Upstream details, scene content and tokens are never logged/returned. Each upstream read has a five-second timeout; client transport/job boundaries are 15/16 seconds.

The client validates version, request, trace, fingerprint, allowed state/code, retryability, zero cost/attempts and null output. Unexpected generated text/images or live-success states are rejected. No response can update dialogue/narration.

## Jobs, retries and recovery

States: `draft -> submitting -> disabled | rejected | failed`. Interrupted submitting checkpoints reopen as `failed/INTERRUPTED`. No worker, polling loop, automatic retry or accepted page is implied. Two total manual transport attempts are allowed per unchanged request across reloads; disabled/rejected responses are terminal. Scene edits start a new request. Dialogue/narration edits retain the illustration identity because their words never enter its input.

Checkpoint exact page fields, pinned source IDs/checksum, correlation IDs and attempt count **before** a call. Failed checkpoints prevent calls and keep fields in memory. Account invalidation/disposal fences late completions. Unreadable/newer-format records remain until explicit discard. Recovery shares drawing storage's existing namespace and session fence. Sign-out clears both; confirmed source deletion clears its corresponding local page draft. Other devices' copies cannot be recalled.

Disabled replay is side-effect-free, with no work or cost. It is **not a durable server idempotency ledger**. Before live calls, Stage 6 must atomically reserve owner-scoped keys and payload hashes, reject key/payload conflicts, enforce quotas/cost reservations and settle every attempt. A reviewed live contract/client path must preserve disable, validation, moderation and recognition gates. This implementation authorizes no paid benchmark.

## Deterministic page draft

Open a saved version and choose Plan a story page. One local page draft belongs to each saved version. Scene, exact dialogue and exact narration are separate fields. Autocorrect, suggestions, automatic capitalization and automatic truncation are disabled. App-rendered text uses a fixed 600-unit width, 360-unit artwork region and bundled Nunito metrics. Device width scales the sheet; height grows to include every line without ellipsis. Form controls support enlarged text and scrolling. Font fallback outside the bundled face's coverage can vary by platform.

The preview shows the original artwork, explicitly labeled as a draft. Above 20,000 code units per text field, preview pauses while complete fields/records remain retained. Device persistence is best effort, quota-limited and unencrypted. Immediate tab/process loss, blocked storage or failed quota can still lose unsaved work; recovery warnings advise keeping the page open/copying words. Cloud stories/pages, accepted live illustrations and story export remain Stage 7.

## Verification

`scripts/check.ps1` runs Flutter checks/release compilation plus Node 24+ offline gateway tests. `npm test --prefix backend` runs only the offline handler tests. No provider is contacted.

For hosted checks, prepare two fictional accounts with `backend/tests/prepare_auth_fixtures.py` and apply generated create SQL as documented in `backend/README.md`. Run `node backend/tests/illustration_gateway_smoke.mjs`, serve a configured release on port 8766, then run `node backend/tests/story_browser_smoke.cjs`. Mandatory cleanup: `character_deletion_smoke.mjs --cleanup`, verify zero fixture Storage objects/characters, apply Auth cleanup and verify zero accounts, remove ignored fixture JSON, stop the preview server. Never use real family accounts/artwork.
