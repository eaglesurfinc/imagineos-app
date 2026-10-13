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
