# Current implementation status

Updated: 2026-10-12 (America/Chicago). `BUILD_PLAN.md` defines acceptance gates.

## Current increment

Stages 0-1 and the Stage 2 account/isolation implementation are complete. Parent email/password sign-up, sign-in, reset/new-password forms, sign-out, session restoration, family loading, and recoverable errors are implemented. Password-recovery events open the parent panel. Offline builds keep the original preview. Configured builds expose account access under For parents.

`parent_profiles`, `families`, and `child_profiles` are deployed with RLS, explicit grants, immutable ownership and child-family links, and a private Auth provisioning trigger. Child profiles store only a nickname. Child-profile management UI, saved characters, upload/drawing, AI, protected parent locks, consent/deletion, and export remain pending.

## Verification

- Final `scripts/check.ps1` passed: formatting, analysis (no issues), all 13 tests, and release web build. The configured release build also passed. No dependency versions changed.
- SQL isolation tests passed on the actual hosted database for two families: own reads/inserts/updates, blocked foreign reads/inserts/updates/deletes, ownership reassignment, linked-child reassignment, forged metadata, unauthenticated access, and anonymous Auth users. Fixtures rolled back.
- Real Auth/Data API tests passed using two temporarily provisioned, confirmed fictional accounts: password sign-in, wrong-password denial, refresh, logout/refresh revocation, family/child isolation, metadata escalation, and anonymous denial.
- Configured release in isolated headless Edge passed sign-in, family loading, reload/session restoration, and sign-out clearing the family view, with no uncaught runtime errors. Phone screenshots inspected. Earlier offline shell phone/tablet/keyboard checks remain recorded in history; the new Auth flow has not had a full tablet/zoom accessibility audit.
- Hosted security advisor returned no findings after migration. The migration history contains `20261013014911_parent_family_access`; local SQL uses that version.
- Deleted temporary API/browser accounts and their cascaded records; cleanup returned zero remaining test accounts. Local temporary credential/SQL files removed.
- Known nonblocking build warning: Cupertino font family not bundled; Material icons render.

## Hosted targets and configuration

Supabase: `imagineos-dev`, ref `hgsivbqmbcliqbstrkdz`, eaglesurf's Org, `us-east-2`, created on Free at quoted $0/month. Public identity is in `backend/project.json`. URL/publishable key remain in ignored local config. No server secret or DB password is in Flutter/Git.

The founder confirmed hosted Site URL `https://imagineos-app.vercel.app`, allowed redirects for that origin and both localhost:8766 origins, and email confirmation enabled. The settings endpoint reports email enabled and `mailer_autoconfirm = false`. Hosted settings are founder-confirmed; configuration-management tools remain unavailable. CLI login/linking and Docker replay remain unconfigured.

Vercel: the founder's screenshot confirms the shell loads after commit `d24f32e`; the 404 is resolved. The founder confirmed both build variables set for the next deployment. Vercel tools still cannot access the `koletek` scope (403); remote logs and the new Auth deployment are not independently verified.

## Remaining verification and next action

After the new commit deploys, use an adult test account under For parents to verify signup email delivery, confirmation callback, sign-in, reset email/new-password callback, refresh, and sign-out at the live origin. Temporary preconfirmed fixtures did not test actual mail delivery. No SMTP provider was added; built-in hosted email restrictions/rate limits may require a separately approved delivery decision. Do not disable verification to bypass those limits.

Then continue Stage 3: add character/version/asset migrations and private storage policies, child-profile selection/management, upload an original drawing, name/save/reopen it, and run cross-family asset access and interruption tests. Keep fictional adult-created content until pilot readiness is established. The later protected parent mode remains a separate acceptance gate.
