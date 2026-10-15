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

`characters` holds identity and a child/family relationship; `character_versions` holds append-only names and version numbers; `original_assets` holds the private path, MIME type, size, checksum and pending/ready/cancelled state. Read through `original_uploads`, a SECURITY INVOKER view. All underlying tables use family RLS and grant only SELECT to clients.

Use `reserve_original`, `finish_original`, and `cancel_original` RPCs for state transitions. Their invoker wrappers delegate to explicitly granted functions in the unexposed `imagineos_upload_private` schema, which check authenticated database ownership and qualify all names. The Auth provisioning schema remains inaccessible to clients. Never bypass these transitions or grant direct table mutation to fix a client error.

The private bucket `character-originals` caps each object at 5 MB and permits only PNG/JPEG/WebP. Paths are server-assigned family/asset UUIDs. Storage policies deny unreserved uploads, all overwrites/upserts, and deletion of ready files. Only pending files can be discarded. Do not delete Storage metadata using SQL: remove files through Storage API first.

To verify Stage 3, prepare the two fictional accounts as above, apply their generated create SQL, then run from repository root:

```powershell
node backend/tests/character_storage_smoke.mjs
flutter build web --dart-define-from-file=config/supabase.local.json
python -m http.server 8766 --bind 127.0.0.1 --directory build/web
```

In another terminal, run `node backend/tests/character_browser_smoke.cjs`. It uses an isolated headless Edge profile; set `IMAGINEOS_BROWSER_PATH` for another Chromium executable. Node 24+ is required. It tests the real file picker, save, reopen, intentional version update, and reload, and independently checks both byte streams through REST/Storage. Temporary screenshots contain fictional data only. These checks do not send email.

Mandatory cleanup, including after failed tests: through an authorized SQL connection apply `reset_originals` from the ignored fixture SQL file, which targets only the two generated fictional families. This privileged test-only reset allows their ready objects to be removed; it is never a product operation. Run `node backend/tests/character_storage_smoke.mjs --cleanup` to remove files via Storage and cancel remaining reservations. Finally apply the fixture `cleanup` SQL to delete their Auth users and cascaded records. Assert zero fixture accounts/objects remain, then remove the ignored fixture JSON files. Never apply that reset to real users, real artwork, or another project.
