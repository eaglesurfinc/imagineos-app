# Preserved sources and requirement mapping

This new build repository consolidates current implementation files. No original repository, document, commit, or working change was deleted. Full source histories remain in their original repositories. Only reviewed build material is intended for public publication here.

| Source repository | Base commit | Imported material |
| --- | --- | --- |
| Eaglesurf-imagineOS/imagineos-mobile | `3b567d6` | Flutter lib/web source, pubspec/lockfile, development scripts, ignore rules |
| Eaglesurf-imagineOS/imagineos-backend | `32c8c2e` | Current working CLI package/lockfile and generated Supabase config, including previously uncommitted setup |
| Eaglesurf-imagineOS/imagineos-founder-bible | `ba53d93` | Compact requirement extraction only; full writings stay separate, including existing agent-independent working edits |

`import-manifest.json` records SHA-256 hashes of original mobile source/web/scripts at import time, before deliberate changes in this repository. Source-repository browser/build evidence remains in `imagineos-mobile/docs/BUILD_STATUS.md` and `BROWSER_VERIFICATION.md`; new changes need new verification.

## Source paths in the separate Founder Bible

| Build topic | Source documents/folders |
| --- | --- |
| Non-negotiable creative guarantees | `00-Constitution/01-Constitution.md`, `06-Creative-Trust.md`, `07-AI-Boundaries.md`; source client/backend instructions prohibit even requested AI dialogue rewriting |
| MVP and exclusions | `02-Product/06-MVP-Definition.md`, `07-MVP-Requirements.md`, `09-Non-Goals.md` |
| Child flows, drawing/upload, library, parent UX, accessibility | `03-UX/` |
| Stack, authentication, privacy, gateway, deployment | `04-Architecture/` |
| Users/families, characters/versions, stories, assets, jobs, RLS | `05-Database/` |
| Original reference, versioning, recognition and continuity | `06-Character-Engine/` |
| Provider abstraction, validation, retries, safety, quotas/cost | `07-AI/` |
| Delivery sequence and reviews | `08-Sprints/` and `10-Business/1000-Dollar-Build-Plan.md` |
| Pilot, monitoring, support, rollback and launch readiness | `09-Launch/` |
| Spending envelopes, research and business work | `10-Business/1000-Dollar-Build-Plan.md`, `10-Business/`, `12-Research/` |
| Open decisions and source authority | `11-Decisions/`, relevant `Open-Questions.md`, `AGENT_CONTEXT.md` |

If deeper source reading is needed, the founder can provide the specific document from the separate planning repository. Do not require the whole corpus for routine implementation, and do not invent answers to unresolved product questions. Material requirement changes must remain consistent with the Constitution and be reflected in both the engineering contract and relevant source writings.
