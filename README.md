# ImagineOS

Kids create. AI illustrates.

This is the implementation repository: Flutter client at the root and Supabase tooling under `backend/`. Start here with any coding agent. The original product, philosophy, business, and research writings remain in the separate Founder Bible; they are not required downloads for routine build tasks.

Current state: initial source consolidation with Supabase configuration preparation. Hosted project creation is on hold. The new SDK dependency has not been downloaded or verified; run `flutter pub get` to update the imported baseline lockfile, then the checks below before treating this increment as build-ready. See `docs/STATUS.md` for the exact evidence.

## Build in order

1. Read [AGENTS.md](AGENTS.md) and the compact [requirements](docs/REQUIREMENTS.md).
2. Check [STATUS.md](docs/STATUS.md) for evidence and the next task.
3. Follow [BUILD_PLAN.md](docs/BUILD_PLAN.md), completing one acceptance gate at a time.
4. Record material choices in [DECISIONS.md](docs/DECISIONS.md).

## Run the shell

Validated baseline: Flutter 3.47.2 stable / Dart 3.13.2. Install Flutter, then from this directory:

```powershell
flutter pub get
flutter run -d edge --web-port 8766
```

Without Supabase configuration this runs the existing shell offline. It has an empty character library and parent information; it does not sign users in, save drawings, or generate images.

## Connect Supabase when project creation is authorized

Follow [backend/README.md](backend/README.md). Copy `config/supabase.example.json` to the ignored `config/supabase.local.json` and replace the placeholders with your development project URL and publishable key. Then run:

```powershell
flutter run -d edge --web-port 8766 --dart-define-from-file=config/supabase.local.json
```

These values are compiled into the browser application. Only a publishable key belongs here. Database passwords, service-role keys, secret API keys, and AI provider keys must stay server-side. A configured client is not a completed authentication feature.

## Verify

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1
```

The check script resolves dependencies, checks formatting, analyzes code, runs tests when present, and builds web. It makes no paid AI calls. For a configured web build use `flutter build web --dart-define-from-file=config/supabase.local.json`.

Vercel deployment is deferred. A public repository does not change hosting-plan eligibility; Vercel Hobby is limited to personal, noncommercial use. Native Android/iOS releases remain separate future distribution work.
