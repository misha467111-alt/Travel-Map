# Travel Map — Persistent Engineering Rules

These are long-term repository rules. They are not instructions to implement anything now.

## Project direction
- Cross-platform Flutter app (Android + iOS).
- Build structure-first: (1) working architecture and product flows, (2) correctness and regression safety, (3) visual/reference polish later.
- Do not polish screens for final visual fidelity during architectural phases.

## Journey (core feature)
- Long-term flow: Start → GPS recording → Pause/Resume → Moments → Finish → Summary → History → Details/Timeline → Replay → future 3D experience.
- Do not jump ahead to later Journey phases unless explicitly instructed.

## Offline-first architecture
- Path: UI → controller/domain → local Drift persistence → existing sync machinery.
- No parallel persistence paths. No direct Supabase calls from Journey presentation UI when a controller/repository/sync path exists.
- Local Journey features must not depend on network availability unnecessarily.

## Canonical persisted state
- Persisted Drift Journey data is the canonical recorded-route state; do not add a second canonical in-memory collection.
- Prefer existing Drift streams/watch queries for reactive UI.
- Maintain owner and `recordedRouteId` isolation.

## GPS (protected subsystem)
- Do not change sampling, filtering, point acceptance, recording thresholds, recovery semantics, or location-stream behavior unless the task explicitly requires it.
- Do not classify physical GPS drift as an app defect without evidence; external interference may exist during QA.

## Journey statistics
- The Phase 0 statistics engine is canonical. Do not duplicate distance/time/pause/speed/elevation/pace calculations in UI or elsewhere, and do not change its semantics casually.
- If integration seems to require changing canonical statistics behavior, stop and report the conflict first.

## Moments
- Use the existing local waypoint persistence and sync lifecycle.
- Telemetry (coordinates, altitude, timestamp, owner, route identity, waypoint identity) is system-controlled; user edits affect only intended metadata.
- Delete via the existing tombstone/sync lifecycle.

## Finish vs Discard (never merge)
- Finish: completes a Journey, preserves canonical data, may enter the sync lifecycle.
- Discard: is not a successful completion and must not create a completed summary/history entry through a new path.

## Backend protection
- Do not modify Supabase schema, migrations, RLS, RPCs, Storage, Edge Functions, or production data unless the task explicitly authorizes it.
- If a feature appears to need backend/protocol redesign without authorization, stop and report it.

## Existing architecture first
Before implementing: inspect the existing implementation; identify canonical sources of truth; identify existing repository/controller/database/sync paths; reuse them where safe; avoid duplicate systems. Check references before assuming a helper/path is unused.

## Scope discipline
- Modify only files needed for the requested phase.
- No opportunistic cleanup, unrelated refactors, dependency upgrades, or visual redesign unless requested.

## Testing / resource discipline
- Usage limits matter. Run focused tests first; do not repeatedly run the full Flutter suite or Android builds.
- Broad regression only after implementation stabilizes; `flutter analyze` near final verification; Android debug build once when required.
- Do not spend significant time repairing ADB unless asked.
- Never fabricate test or QA results. Report DEFERRED/BLOCKED checks clearly. Test counts must come from actual results, not arithmetic.

## Physical QA
- Never bypass device security or enter PINs/passwords; ask the user to unlock.
- Avoid production mutations during QA when possible.
- Never claim physical QA PASS unless actually observed.

## Git safety
- Implementation phases stop before checkpoint. Unless the task explicitly authorizes it: no `git add`, commit, push, force push, reset, discard, or stash of user work.
- At authorized checkpoints: review exact scope, verify no secrets/artifacts, commit only approved files, never force push, verify `HEAD == origin/main` after pushing.
- Never commit: `.env`, secrets, APKs, screenshots, UI dumps/XML, temporary QA artifacts, logs.

## Reporting
- Distinguish verified facts, assumptions, deferred checks, and blocked checks. No PASS for anything not actually verified.
- When a task says STOP after a phase/checkpoint, stop there and do not begin the next phase.
