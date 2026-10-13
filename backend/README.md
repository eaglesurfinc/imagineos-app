# Backend development

Supabase CLI 2.120.0 is pinned in `package.json`. No application migrations or custom schema exist yet. Current verification evidence belongs in the root `docs/STATUS.md`.

## Hosted development connection

The authorized Free development project is `imagineos-dev` in eaglesurf's Org, region `us-east-2`. Its ref and API URL are recorded in [project.json](project.json). Use this target; do not create additional projects or upgrade its plan as a routine build step.

1. Copy root `config/supabase.example.json` to ignored `config/supabase.local.json`, using the URL from `project.json` and modern publishable key from the project's Connect dialog. The current workstation is already configured.
2. Run `flutter run -d edge --web-port 8766 --dart-define-from-file=config/supabase.local.json` from the repository root.
3. Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-backend.ps1` from the root. It checks Auth reachability and the expected denial of schema discovery to publishable keys. It does not test table access or sign-in.
4. Use an authorized server-side SQL connection for a database probe: `select 1 as connection_ok;`. Never put that connection's credentials in client config.

Use [official Flutter setup](https://supabase.com/docs/guides/getting-started/quickstarts/flutter) and [client initialization](https://supabase.com/docs/reference/dart/initializing). Only a modern publishable key belongs in Dart defines; compiled browser output exposes those values.

## Auth setup before Stage 2

Open the development project's Authentication settings. Review Site URL and exact allowed redirects for `http://127.0.0.1:8766` and `http://localhost:8766`; keep email verification enabled and verify the intended provider/email-delivery behavior before testing account creation. No production origin is authorized yet.

`supabase/config.toml` is a local template, with these development origins and email confirmation enabled. It has not been applied to hosted Auth. Current connected tools provide no Auth configuration management, so hosted settings remain an explicit unfinished gate. Endpoint reachability alone cannot validate email callbacks.

## CLI and future migrations

```powershell
cd backend
npm ci
npm run supabase -- --version
npm run supabase -- migration new <descriptive_name>
npm run supabase -- db push --help
```

Discover current options with `--help`. Commit migration SQL here before applying it. Authenticate the CLI through its supported login flow or an external environment token, then explicitly select ref `hgsivbqmbcliqbstrkdz` using the supported project option/link command. Verify the target and review a dry run before applying approved migrations. Local CLI authentication/linking is not configured on this workstation. Keep access tokens and database passwords outside Git. Never reset a database as routine verification.

Hosted development does not require Docker. Local stack replay does; installation was declined and local database replay remains unverified. Before schema changes, add explicit grants/RLS and real cross-family access tests. AI remains disabled until its approved stage.
