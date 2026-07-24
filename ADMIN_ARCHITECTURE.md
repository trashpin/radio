# ExplorerOS Admin — Architecture

Companion to `ADMIN_ANALYSIS.md`. Defines how the redesigned admin is built and
how it reuses the existing ExplorerOS codebase.

## Decision

Build the admin as a **Flutter-web application in this repository**, sharing the
mobile app's Dart models, repositories, services, and design tokens against the
**same Supabase project**. This maximizes reuse (per the brief), keeps one source
of truth for schemas, and avoids a parallel JS/TS stack that would duplicate the
data layer.

- **Entrypoint:** `lib/main_admin.dart` (separate `flutter run/build -t`).
- **App root:** `lib/features/admin/admin_app.dart` (own `MaterialApp`, light+dark).
- The consumer mobile app (`lib/main.dart`) is untouched.

## Folder structure

```
lib/
  main_admin.dart                     # web entrypoint for the admin
  features/admin/
    admin_app.dart                    # MaterialApp + theme mode
    admin_modules.dart                # AdminModule enum: title, icon, group, status
    admin_state.dart                  # Riverpod: selected module, theme mode, search
    admin_stats.dart                  # AdminStats model + service + provider (counts)
    widgets/
      admin_widgets.dart              # StatCard, StatusBadge, AdminPageHeader,
                                      # AdminSectionCard, EmptyState, breadcrumb
    presentation/
      admin_shell.dart                # responsive sidebar + top bar + content
      dashboard_page.dart             # KPI widgets, recent activity, storage
      content_pages.dart              # Parks, Media Library, Stories, ModulePlaceholder
```

Design tokens and shared widgets are imported from `lib/core/theme/**` and
`lib/shared/**` (no duplication).

## Components (reusable admin UI)

- `AdminStatCard` — KPI tile (label, value, icon, trend/hint).
- `StatusBadge` — published/draft/review/error pills.
- `AdminPageHeader` — title + subtitle + actions (New, bulk).
- `AdminSectionCard` — rounded surface used by tables/panels.
- `AdminDataTable` (via `DataTable`) — sortable content lists with row actions.
- `EmptyState` — consistent "no rows yet" panel.
- `AdminBreadcrumb` — Home / Module path.

## Pages / modules (sidebar)

Grouped for scale, matching the brief (22 modules):

- **Overview:** Dashboard.
- **Content:** Parks, Locations, Map Editor, Trails, Routes, Stories,
  Historical Events.
- **Audio:** Explorer Radio, Music Library, Albums.
- **Nature:** Wildlife, Plants, Birds.
- **Assets:** Media Library, AI Content, Downloads.
- **Platform:** Users, Subscriptions, Analytics, Settings.

Each module maps to an `AdminModule` enum value with a title, icon, group, and a
`status` (`ready` vs `planned`). `ready` modules render real
data-backed pages; `planned` modules render a consistent `ModulePlaceholder`
describing scope + the backing table, so the full IA is navigable now and each
page is a one-line swap later.

**Implemented in this phase (data-backed):** Dashboard, Parks (`destinations`),
Media Library (`media`), Stories (`stories`).

## Database relationships (target, normalized on Base44 schema)

```
destinations (destination_id PK)
  ├─ stops (destination_id FK)              # "Locations"
  │    └─ media (stop_id FK)
  ├─ stories (destination_id FK, hero_media_id → media, stop_id → stops)
  ├─ knowledge_articles (destination_id FK, stop_id FK, hero_media_id → media)
  └─ media (destination_id FK)              # audio in `mp3` bucket

# Roadmap tables (create via migration when modules are built):
parks, trails, routes, wildlife, plants, birds, historical_events,
radio_stations, songs, albums, music_metadata, users/profiles(+roles),
subscriptions, analytics_events.
```

The admin reads/writes through the generic `SupabaseReadRepository` /
`SupabaseSyncRepository`, so adding a module = model + repository + page.

## Services

- **Reused:** `SupabaseService`, all content repositories, `MediaRepository`,
  `MusicStorageService`, `MusicWriter`, `BulkImportService`.
- **New (admin):** `AdminStatsService` (dashboard counts via Supabase `count`),
  and Riverpod list providers for admin tables. Auth/roles service is on the
  roadmap (Supabase Auth + a `profiles` table with a `role` column).

## Data flow

```
Supabase ── repositories ── Riverpod providers ── admin pages ── AdminShell
                                   ▲
                            AdminStatsService (counts)
```

State: `adminSelectedModuleProvider` (nav), `adminThemeModeProvider`
(light/dark), `adminSearchProvider` (global search). Selecting a sidebar item
updates the selected module; the shell swaps the content pane and breadcrumb.

## Performance

- Lists use the repository cache (`CacheStore`) and are paginated client-side;
  server-side range pagination is the next step for large tables.
- Counts use Supabase `count(exact)` rather than fetching rows.
- Missing tables degrade gracefully (count → 0, list → empty) so the admin runs
  against the current partial schema without errors.

## Auth & permissions (roadmap)

Supabase Auth for sign-in; a `profiles` table with `role ∈ {administrator,
editor, content_creator, guide, read_only}`; RLS policies gating writes by role.
The UI already routes all writes through `SupabaseSyncRepository`, so enforcing
roles is a backend/RLS concern plus a client-side capability guard.

## Future expansion

1. Create roadmap tables via migration; flip each module `planned → ready`.
2. Visual Map Editor: reuse `google_maps_flutter`; click-to-create `stops`,
   draggable markers writing lat/lng, trigger-radius circles, boundary overlays.
3. Bulk media/music upload UI on top of `MusicStorageService` + importers.
4. AI Content tools via a Supabase Edge Function calling an LLM (server-side key).
5. Analytics from an `analytics_events` table + charts.
6. Auth + roles + RLS enforcement.
