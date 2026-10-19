# Backend development

Supabase CLI 2.120.0 is pinned in `package.json`. The first parent/family migration is tracked under `supabase/migrations/`. Current verification evidence belongs in the root `docs/STATUS.md`.

## Hosted development connection

The authorized Free development project is `imagineos-dev` in eaglesurf's Org, region `us-east-2`. Its ref and API URL are recorded in [project.json](project.json). Use this target; do not create additional projects or upgrade its plan as a routine build step.

1. Copy root `config/supabase.example.json` to ignored `config/supabase.local.json`, using the URL from `project.json` and modern publishable key from the project's Connect dialog. The current workstation is already configured.
2. Run `flutter run -d edge --web-port 8766 --dart-define-from-file=config/supabase.local.json` from the repository root.
3. Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-backend.ps1` from the root. It checks Auth reachability and the expected denial of schema discovery to publishable keys. It does not test table access or sign-in.
4. Use an authorized server-side SQL connection for a database probe: `select 1 as connection_ok;`. Never put that connection's credentials in client config.

Use [official Flutter setup](https://supabase.com/docs/guides/getting-started/quickstarts/flutter) and [client initialization](https://supabase.com/docs/reference/dart/initializing). Only a modern publishable key belongs in Dart defines; compiled browser output exposes those values.

## Parent account model

| Table | Purpose | Client permissions |
| --- | --- | --- |
| `parent_profiles` | Auth user ID and creation time | Read self |
| `families` | One server-assigned parent per family | Read own family |
| `child_profiles` | Family ID, nickname (1-40 characters), creation time | Read/create/rename/delete within own family |

Every table has RLS and explicit grants. Parent/family provisioning is handled by a private Auth trigger. No client can set a parent role, assign owners, or move children between families. Child creators retain creative authorship; these relationships control account access only. Child-profile management UI follows in the saved-character increment.

The founder confirmed Site URL `https://imagineos-app.vercel.app`, that origin plus `http://127.0.0.1:8766` / `http://localhost:8766` as allowed redirects, and email confirmation enabled. The public Auth settings endpoint also reports automatic confirmation disabled. The CLI template remains local configuration, not a hosted settings deployment. Verify real signup confirmation/reset delivery before inviting anyone; built-in email service restrictions and rate limits still apply. Do not disable email confirmation to make a test pass.

## Verify access boundaries

Run `tests/family_isolation.sql` through an authorized development SQL connection. It creates fictional fixtures in a transaction, assumes actual `authenticated`/`anon` roles with simulated claims, checks cross-family reads/writes and escalation, then rolls back. It is a database policy test, not a full Auth login test.

For real Auth/Data API checks, from repository root:

```powershell
python backend/tests/prepare_auth_fixtures.py
```

The script verifies the dedicated project and generates ignored `config/auth-test.local.json` (random temporary credentials) and `config/auth-fixtures.local.json` (create/cleanup SQL). Through an authorized server-side connection, apply the generated `create` SQL, then run `node backend/tests/auth_api_smoke.mjs`. Always apply the generated `cleanup` SQL afterward, including on failure; assert `remaining_test_accounts = 0` before deleting the local fixture files. The fixtures directly provision confirmed fictional Auth users and identities for testing; they deliberately do not send email or test confirmation delivery. Never use this setup flow for real accounts or another environment. Ordinary Flutter tests use a fake account service and never send emails.

## CLI and future migrations

```powershell
cd backend
npm ci
npm run supabase -- --version
npm run supabase -- migration new <descriptive_name>
npm run supabase -- db push --help
```

Discover current options with `--help`. Review and track migration SQL here before applying it. Keep local filenames aligned with hosted migration history when using the migration API. Authenticate the CLI through its supported login flow or an external environment token, then explicitly select ref `hgsivbqmbcliqbstrkdz` using the supported project option/link command. Verify the target and review a dry run before applying approved migrations. Local CLI authentication/linking is not configured on this workstation. Keep access tokens and database passwords outside Git. Never reset a database as routine verification.

Hosted development does not require Docker. Local stack replay does; installation was declined and local database replay remains unverified. Before schema changes, add explicit grants/RLS and real cross-family access tests. AI remains disabled until its approved stage.

## Character originals and private Storage

`characters` holds identity and a child/family relationship; `character_versions` holds append-only names and version numbers; `original_assets` holds the private path, MIME type, size, checksum and pending/ready/cancelled/deleting state. Read through `original_uploads`, a SECURITY INVOKER view. All underlying tables use family RLS and grant only SELECT to clients.

Use `reserve_original`, `finish_original`, and `cancel_original` RPCs for state transitions. Their invoker wrappers delegate to explicitly granted functions in the unexposed `imagineos_upload_private` schema, which check authenticated database ownership and qualify all names. The Auth provisioning schema remains inaccessible to clients. Never bypass these transitions or grant direct table mutation to fix a client error.

The private bucket `character-originals` caps each object at 5 MB and permits only PNG/JPEG/WebP. Paths are server-assigned family/asset UUIDs. Storage policies deny unreserved uploads, all overwrites/upserts, and direct deletion of ready files. Pending files can be discarded; explicit character/version deletion first marks selected files as deleting. Do not delete Storage metadata using SQL: remove files through Storage API first.

To verify Stage 3, prepare the two fictional accounts as above, apply their generated create SQL, then run from repository root:

```powershell
node backend/tests/character_storage_smoke.mjs
flutter build web --dart-define-from-file=config/supabase.local.json
python -m http.server 8766 --bind 127.0.0.1 --directory build/web
```

In another terminal, run `node backend/tests/character_browser_smoke.cjs`. It uses an isolated headless Edge profile; set `IMAGINEOS_BROWSER_PATH` for another Chromium executable. Node 24+ is required. It tests the real file picker, save, reopen, intentional version update, and reload, and independently checks both byte streams through REST/Storage. Temporary screenshots contain fictional data only. These checks do not send email.

Mandatory cleanup, including after failed tests: run `node backend/tests/character_deletion_smoke.mjs --cleanup` to remove all artwork for the two fictional families through Storage and then finalize their deletion. Verify zero Storage objects under those family UUID prefixes, then apply fixture Auth `cleanup` SQL and assert zero remaining fixture accounts before removing ignored fixture JSON files. No privileged asset-state reset is required for this workflow. Never delete Storage object metadata through SQL.

## Explicit character/version deletion

`begin_character_deletion` and `finish_character_deletion` take `p_character_id` and optional `p_version_id` (null means the entire character). The begin call resolves ownership, marks selected assets, and returns all selected paths. Remove those through Storage, then finalize; never delete `storage.objects` rows through SQL. Retry both calls after interruption. Direct client writes to character/version/asset tables remain denied. The last saved version requires whole-character deletion.

With the prepared fictional accounts, run `node backend/tests/character_deletion_smoke.mjs`. It tests version removal, whole deletion including unfinished uploads, two-family isolation, interrupted cleanup/new sessions, direct-delete denial, non-reused version numbers, last-version protection, and stale-request resurrection prevention. Its finally block removes all remaining artwork for these fixture families through the new deletion flow. For cleanup without recreating tests use `node backend/tests/character_deletion_smoke.mjs --cleanup`.

For the complete browser flow, prepare fixtures and run the Stage 3 storage test first, serve a configured release on port 8766, then run `node backend/tests/character_browser_smoke.cjs --delete`. This additionally verifies cancel, selected-version removal, reopening the remaining original after reload, and whole-character deletion against REST/Storage. Fresh object URLs avoid mistaking previously cached downloads for current stored files. Only fictional fixtures may be used.

After these tests, verify zero Storage objects under the two generated family UUID prefixes, apply fixture Auth cleanup SQL, and assert zero remaining fixture accounts before deleting local fixture JSON files. The new cleanup option replaces the privileged asset reset for this path. Private deleted-request tombstones disappear with their fixture families.

## Drawing and extraction browser verification

Prepare fictional accounts and apply their generated create SQL as above. Serve a configured release on port 8766, then run `node backend/tests/drawing_browser_smoke.cjs` from the repository root. It does not require the Stage 3 storage fixture file. Node 24+ and isolated Edge/Chromium are required. It draws on a phone canvas, reloads an editable device draft and its exported selection, saves/reopens through real Auth/REST/Storage, and extracts a generated fictional drawing from paper and a patterned background. It checks original bytes, transparent derivative pixels, version identity, foreign-family download denial, zoom, and sign-out draft cleanup. Screenshots in the OS temporary directory contain fictional artwork only.

Always use the Storage/API deletion cleanup and Auth cleanup procedure above, including after a failed browser run. This test creates no paid calls, sends no email, and must never target real family accounts.

For the later precision/input/device-save increment, serve an **offline** release (`flutter build web`, then `python -m http.server 8766 --bind 127.0.0.1 --directory build/web`) and run `node backend/tests/drawing_precision_browser.cjs`. It seeds fictional device drafts without backend accounts, checks line-preserving paper extraction and comparison, selection/delete/undo, shape clips and lasso cutouts, connected removal, pen pressure events, touch navigation without stray paint, and an actual downloaded transparent PNG. Fictional screenshots/downloads stay under ignored `build/drawing-browser-downloads/`. No Auth fixtures, SQL, Storage cleanup, or paid services are involved. Browser input emulation does not verify physical Bluetooth pairing or every tablet's hardware.

## Disabled illustration gateway (Stage 5)

The versioned contract, source/reference rules, recovery and two-attempt manual retry ceiling are in [ILLUSTRATION_GATEWAY.md](../docs/ILLUSTRATION_GATEWAY.md). The `illustration-gateway` function requires JWT verification, validates the user and reads the exact source through caller-scoped RLS. Its only authorized success is disabled, with null output, zero provider attempts and zero cost. No AI key, provider adapter, secret client credential, new dependency or schema migration is involved.

Run `npm test --prefix backend` with Node 24+ for offline handler tests. After preparing the two fictional Auth fixtures as above, run `node backend/tests/illustration_gateway_smoke.mjs`. It creates fictional ready source versions and checks disabled replay, correlation/hash, two-family access, mismatched references, override rejection, anonymous denial and CORS. It writes ignored `config/stage5-fixture.local.json` for `story_browser_smoke.cjs`, which needs the configured release served on port 8766. Always perform the existing Storage/API deletion cleanup and zero-object check, then Auth cleanup and zero-account check, before removing these ignored fixture files. The browser captures fictional screenshots under ignored `build/story-browser/`.

To deploy this single disabled function from an authenticated CLI, run from the repository root:

```powershell
.\backend\node_modules\.bin\supabase.cmd functions deploy illustration-gateway --workdir backend --project-ref hgsivbqmbcliqbstrkdz --use-api
```

The pinned CLI help confirms `--use-api` bundles server-side without Docker. Keep JWT verification enabled; do not use `--no-verify-jwt` or `--prune`. Deployment replaces this named function immediately on the dedicated development target. The initial deployment was made through the connected Supabase tool; local CLI login is still separate.
