# Stage-by-stage build plan

This is the execution checklist for the existing MVP, from foundation to a controlled pilot. Stages are acceptance gates, not equal percentages of engineering effort. “100%” means all MVP and pilot-readiness gates below have evidence; it does not mean every future product idea is built. Keep actual progress and evidence only in `STATUS.md`.

For every task: inspect current work → implement the smallest listed outcome → run relevant checks → try the affected flow → record evidence → proceed to the next incomplete task. A passing later task does not waive an earlier gate.

## Stage 0 — Preserve the foundation

- [x] Import the existing Flutter shell and backend CLI/configuration into one build repository without copying secrets, caches, or private planning history.
- [x] Extract compact requirements and preserve links/provenance to the unchanged full writings.
- [ ] Complete current repository checks and record the new baseline.
- [x] Publish the reviewed initial commit to `eaglesurfinc/imagineos-app` as public.

Gate: a fresh checkout can build using the README; original repositories and recorded work remain available; publication contains only reviewed build material.

## Stage 1 — Hosted development connection

- [ ] Founder authorizes creation of the development project and confirms current cost/organization. Currently on hold.
- [ ] Create/identify the dedicated Supabase development project; record its identity without privileged credentials.
- [ ] Configure Flutter using URL/publishable key; handle missing or invalid configuration without a blank screen.
- [ ] Verify configured browser startup, Auth endpoint reachability, and a database test query. Record hosted checks separately from offline builds.
- [ ] Review auth URLs, email/provider settings, and migration procedure for the development target.

Gate: the app demonstrably connects to the intended development services. No claim of working sign-in yet. Hosted development does not require installing Docker; local replay checks remain a separate environment requirement.

## Stage 2 — Parent access and family isolation

- [ ] Record the minimum parent/family/child-profile schema and chosen parent sign-in method; minimize collected data.
- [ ] Create versioned migrations and explicit access policies/grants. Require server-controlled ownership; deny anonymous access to family records.
- [ ] Build parent sign-up/sign-in, sign-out, session restoration, and recoverable auth errors.
- [ ] Test two independent families, unauthenticated access, role escalation, ownership reassignment, and linked-resource access.

Gate: an adult can sign in and return to their own family context; attempts to access another family's data fail. Tests run against the actual database, not only mocked clients.

## Stage 3 — Original upload and saved-character loop

- [ ] Add character, explicit version, and asset metadata plus private storage policies/migrations.
- [ ] Upload an original drawing, name it, save it, and show it in the library.
- [ ] Close/reopen and retrieve the same source image and identity.
- [ ] Make intentional updates create new versions; preserve old references.
- [ ] Test interrupted uploads, failed saves, retries, orphan cleanup, and cross-family asset access.

Gate: original → save → restart → reopen works without data loss. This is the first useful character milestone.

## Stage 4 — Simple in-app drawing and child flow

- [ ] Finalize the minimal brush/color/undo controls within the existing drawing scope.
- [ ] Draw and save through the same character/version pipeline as uploaded originals.
- [ ] Add clear creation actions and usable empty, loading, error, and recovery states.
- [ ] Verify phone/tablet layouts, enlarged text/zoom, keyboard access, and interruption recovery.

Gate: both in-app drawing and paper upload produce persistent, revisitable originals. No extra art-suite scope.

## Stage 5 — Disabled gateway and deterministic story structure

- [ ] Define versioned gateway request/response contracts, trace IDs, and an explicit disabled result.
- [ ] Keep exact dialogue in application data and implement deterministic text layout independently of image generation.
- [ ] Define AI job states, idempotency, validation/failure contracts, retry ceilings, and draft preservation.
- [ ] Verify disabled/failure behavior without paid calls or server credentials in the client.

Gate: requests cannot accidentally invoke a live provider, rewrite dialogue, or lose drafts.

## Stage 6 — Bounded live illustration benchmark

- [ ] Choose the provider through a recorded technical decision; implement a server-side adapter.
- [ ] Add input/output validation, moderation, atomic quota/budget reservation and settlement, family limits, and kill switch.
- [ ] Obtain founder authorization for the first capped paid benchmark (existing plan caps the first release at $25 from the $200 AI allocation).
- [ ] Benchmark varied fictional adult-created drawings across scenes; record recognition, latency, failures/retries, and cost per accepted output.
- [ ] Set and record acceptable drift, retry, and fallback thresholds; reject unvalidated outputs.

Gate: evidence shows recognizable output with bounded cost and reliable failure handling. Metadata or attractive pictures alone do not establish continuity.

## Stage 7 — Complete story and export

- [ ] Let the child select a saved character/version, direct a scene, and enter exact dialogue/narration.
- [ ] Produce and review a page using validated illustration and app-rendered text.
- [ ] Save/reopen stories and pages with fixed version/asset references.
- [ ] Decide the minimal export format and implement save/download with exact text and preserved artwork references.
- [ ] Test later character updates, interrupted generation/saves, export fidelity, and repeat sessions.

Gate: the complete character → scene → accepted page → save/reopen → export loop works.

## Stage 8 — Protected parent controls and reliability

- [ ] Add protected parent settings and accurate provider/storage/privacy explanations.
- [ ] Implement the approved consent, data visibility, retention, and deletion flows.
- [ ] Test authorization boundaries for parent controls, account deletion/session effects, private assets, and exports.
- [ ] Exercise backup/recovery, failed saves, logging without raw child content, and operational cost limits.

Gate: parent controls are actually protected and privacy/recovery behavior is verified end to end.

## Stage 9 — Controlled pilot readiness

- [ ] Resolve launch jurisdiction and applicable obligations before collecting real family data.
- [ ] Complete safe-output, consent/deletion, security, cost, support, monitoring, incident, and rollback readiness review.
- [ ] Select hosting/distribution with suitable terms and approved costs. Vercel deployment remains deferred; public GitHub visibility does not change Hobby terms.
- [ ] Run a full release rehearsal and document remaining limitations before inviting families.
- [ ] Conduct a small authorized pilot; measure repeat creation, character recognition/ownership, recovery, and accepted-page economics.

Gate: evidence supports a controlled pilot and the core promise. Broader public launch, commercial expansion, native distribution, and future creative formats require their own readiness decisions.

## Work that continues alongside building

Parent research, pricing, market validation, legal/privacy advice, and business decisions stay in the Founder Bible. Use 5–10 parent conversations to test demand for returning to existing characters, with appropriate data handling. Bring only decisions that change implementation into `DECISIONS.md`; do not duplicate the research corpus here.
