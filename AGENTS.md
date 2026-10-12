# Shared implementation instructions

These instructions apply to every coding agent and human contributor. If your tool does not automatically load this file, read it explicitly. Do not create a separate vendor-specific plan.

## Read only what the task needs

Begin with `docs/REQUIREMENTS.md`, `docs/STATUS.md`, and the next incomplete gate in `docs/BUILD_PLAN.md`. Read `docs/DECISIONS.md` before changing architecture. Routine tasks do not require reading the entire Founder Bible. For unresolved product questions, consult the precise source paths listed in `docs/PROVENANCE.md` or ask the founder.

The Constitution remains the highest product authority. Preserve the child as creator, exact child dialogue, original drawings, character recognition, and explicit version history. AI never writes or rewrites dialogue, including on request. Never silently weaken these rules to finish a milestone.

## Work and verify

- Flutter remains the client. Supabase provides Auth, PostgreSQL, and private Storage. AI calls go through an ImagineOS-controlled server gateway. Do not replace the stack when switching agents.
- Inspect branch, working tree, current source, and status before editing. Preserve existing work. Implement one bounded acceptance gate at a time.
- Protect family isolation before accepting drawings. Enable and test RLS on exposed tables and storage, including ownership of linked resources. Never authorize using user-editable metadata.
- Keep secrets, real family data, SDK caches, and build output out of Git. Only fictional adult-created test data is allowed during development.
- Preserve exact dialogue outside generated images. Pin saved pages to character versions. Stored metadata alone does not prove visual recognition.
- Run `scripts/check.ps1` after application changes. Run database/access tests after schema changes. Report checks not run and why; never claim tests passed when none ran.
- Live AI requires input/output validation, moderation, bounded retries, idempotency, atomic quotas, trace IDs, measured costs, and a generation kill switch. Ordinary tests never call paid providers.
- Respect the founder's $1,000 total ceiling and existing allocations. No paid services, credits, or upgrades without authorization.
- Hosted project creation is currently on hold at the founder's request. Docker installation was declined. Do not create a hosted project or install Docker without renewed authorization.
- Vercel deployment is deferred. Publishing code does not authorize deployment or remove a host's commercial-use restrictions.

## Handoff

Update only `docs/STATUS.md` for implementation progress: acceptance criteria met, files/commit, checks and results, limitations, and next concrete task. Update `docs/DECISIONS.md` for material choices and `docs/BUILD_PLAN.md` checkboxes only when their gates are evidenced. Keep all three consistent.

If multiple agents are assigned, give each a bounded task and separate branch/worktree. Avoid concurrent edits to the same files. Integrate and run combined checks before claiming the stage complete. No chat history or private vendor memory should be required to resume.
