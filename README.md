# ImagineOS

Kids create. AI illustrates.

This is the implementation repository: Flutter client at the root and Supabase tooling under `backend/`. Start here with any coding agent. The original product, philosophy, business, and research writings remain in the separate Founder Bible; they are not required downloads for routine build tasks.

Current implementation: parent accounts, creator nicknames, private character upload/save/reopen, immutable versions, crop/rotate/flip, confirmed whole-character or selected-version deletion, and a drawing studio with kits, colors, shapes, fill, erasing, undo/redo and local draft recovery. Extract paper artwork or manually outline a drawing in a busy photo, review it, then save a new version. Originals live in private Supabase Storage. Page planning now keeps exact dialogue/narration in a device draft and fixed-layout preview; the authenticated illustration gateway explicitly returns disabled. Live AI, cloud-saved stories, protected parent locks, and story export remain pending. See `docs/STATUS.md` for verification and deployment status.

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

Use Select area to drag a rectangle, or Lasso select to trace a specific region. Paint, shapes, fill and cleanup stay inside the selection. Delete selection is undoable; Keep only selection previews a cutout; Deselect returns to the whole canvas. Shapes include circles/squares, triangles, diamonds, pentagons, hexagons, stars, hearts and arrows. Paper cleanup protects faint lines using a local page estimate; Compare original checks the result. Remove area offers edge protection and tiny-gap bridging. Ambiguous pale artwork or strong shadows can still need manual erasing.

Save to device exports the current canvas as a PNG without a parent account or cloud save. The browser uses this device's Downloads or save prompt; the destination depends on browser/OS settings. Transparency is preserved and the checkerboard/selection outline is absent from the file. A downloaded PNG is a pixel copy, not a layered project. Device drafts recover completed editable changes when browser storage permits. Reload starts fresh undo history, cloud versions contain PNG pixels, and signing out clears device drawing drafts. Working copies use up to 1536 pixels on their longest edge; source uploads retain their original bytes. Extraction runs locally and does not automatically recognize a subject in a complex background.

Two fingers pan/zoom without painting. Compatible pens use standard device input, including pressure and inverted eraser tips when reported. Pen only lets fingers navigate while a pen draws. Connect a pen explains OS pairing and shows how to check the input indicator; the app does not pair Bluetooth accessories itself. Bluetooth/USB/built-in pen capability depends on the tablet and browser. Physical-device checks remain necessary; the current runnable target is web.

## Canvas text and page planning

Choose Text in the drawing tools, then tap a canvas point. Type exact words, pick one of eight bundled fonts, set size and choose palette/custom colors. Tap existing text with the Text tool to edit it. Device drafts retain text items until pixel cleanup, selection deletion or Merge paint flattens them; Undo restores editability. Cloud versions/downloads are PNG pixels. Select area or Lasso select, focus the canvas and press Delete/Backspace to clear that region; Undo restores it. Text fields keep their normal deletion behavior.

Paper extraction now estimates photo noise as well as lighting and warm/dim page color. Review reports how much paper was cleared; change strength and Compare original before applying. Ambiguous art/page colors still need manual review.

For story planning, open a saved character version and choose Plan a story page. Enter a scene, exact dialogue and optional narration, then review the original-art page draft. Check illustration availability returns disabled; it makes no paid AI call. Reload/reopen the same version to recover its local page draft. Recovery is best effort and sign-out clears it. No cloud story/export is claimed. The [gateway contract](docs/ILLUSTRATION_GATEWAY.md) records fields, access, retries and the live-generation boundary.

## Verify

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1
```

With Flutter/Dart and Node 24+ on PATH, the check script resolves dependencies, checks formatting, analyzes code, runs Flutter and offline gateway tests, and builds web. Check the hosted endpoints separately with `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-backend.ps1`. It makes no paid AI calls. For a configured web build use `flutter build web --dart-define-from-file=config/supabase.local.json`.

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
