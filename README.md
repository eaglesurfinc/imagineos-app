# ImagineOS

Kids create. AI illustrates.

This is the implementation repository: Flutter client at the root and Supabase tooling under `backend/`. Start here with any coding agent. The original product, philosophy, business, and research writings remain in the separate Founder Bible; they are not required downloads for routine build tasks.

Current implementation: parent accounts, creator nicknames, private character upload/save/reopen, immutable versions, crop/rotate/flip, confirmed whole-character or selected-version deletion, and a drawing studio with kits, colors, shapes, fill, erasing, undo/redo and local draft recovery. Extract paper artwork or manually outline a drawing in a busy photo, review it, then save a new version. Originals live in private Supabase Storage. Stories, AI, protected parent locks, and export remain pending. See `docs/STATUS.md` for verification and deployment status.

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

Without Supabase configuration this runs offline with an empty character library, parent information, and a drawing-studio preview. Cloud saving requires a configured signed-in build; generation remains pending.

## Connect Supabase development

Follow [backend/README.md](backend/README.md). Copy `config/supabase.example.json` to the ignored `config/supabase.local.json` and replace the placeholders with your development project URL and publishable key. Then run:

```powershell
flutter run -d edge --web-port 8766 --dart-define-from-file=config/supabase.local.json
```

These values are compiled into the browser application. Only a publishable key belongs here. Database passwords, service-role keys, secret API keys, and AI provider keys must stay server-side. Use the For parents tab to create a parent account, confirm its email, and sign in. See `docs/STATUS.md` for live sign-in, recovery, and signup-confirmation verification results.

## Draw and extract artwork

Choose a creator, then Draw a character. Pick a kit/tool and colors; use drawing to return to the naming/save form. Resume drawing studio continues edits before a save attempt. For a photo, choose the file and name, then Save original and open studio. Existing versions also have Open drawing studio. Remove paper background previews light-paper cleanup; Outline cutout keeps the area you trace in a busy photo. Remove area and the eraser refine remaining background. Review before applying, then Use drawing and Save new version. Earlier saved versions stay unchanged.

Transparent canvases display a checkerboard that is absent from the PNG. Device drafts recover completed changes when browser storage permits; save to the library for persistence. Reload starts fresh undo history, cloud versions contain PNG pixels, and signing out clears device drawing drafts. Working copies use up to 1536 pixels on their longest edge; source uploads retain their original bytes. Extraction runs locally and does not automatically recognize a subject in a complex background.

## Verify

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1
```

The check script resolves dependencies, checks formatting, analyzes code, runs tests when present, and builds web. Check the hosted endpoints separately with `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-backend.ps1`. It makes no paid AI calls. For a configured web build use `flutter build web --dart-define-from-file=config/supabase.local.json`.

## Vercel shell deployment

The repository now includes `vercel.json` and `scripts/vercel-build.sh`. The script installs Flutter 3.47.2 at the verified revision, resolves the committed dependency lockfile, and builds the static website into `build/web`. Generated files stay out of Git; importing the source alone does not generate them.

For the existing `imagineos-app` project in the `koletek` scope, connect `eaglesurfinc/imagineos-app`, production branch `main`, and use these settings:

| Setting | Value |
| --- | --- |
| Root Directory | Repository root (leave blank) |
| Framework Preset | Other |
| Install Command | From `vercel.json` |
| Build Command | `bash scripts/vercel-build.sh` |
| Output Directory | `build/web` |

Remove conflicting dashboard overrides and redeploy the latest commit. Confirm the build log actually runs the Flutter script and its output includes `index.html`, `flutter_bootstrap.js`, and `main.dart.js`. The current app uses internal tab navigation and needs no path-routing rewrite.

With neither `SUPABASE_URL` nor `SUPABASE_PUBLISHABLE_KEY` set in Vercel, the deployed shell runs offline. To enable SDK initialization, set both build variables using the development project's URL and modern publishable key, then rebuild. Never use a service-role or secret API key; both values are compiled into the public browser bundle. The ignored local JSON configuration is not available to Vercel.

This is an early shell, not a family pilot. Current remote deployment verification is pending account access; see `docs/STATUS.md`. Native releases and hosting eligibility remain separate readiness decisions.
