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

## Decisions needed in their stages

- Stage 2: parent sign-in method and minimal explicit family/profile relationships.
- Stage 4: minimum drawing controls.
- Stage 6: illustration provider, recognition/drift thresholds, retry limits, benchmark authorization.
- Stage 7: default export format.
- Stages 8–9: parent controls/consent details, retention/deletion, launch jurisdiction and distribution readiness.
