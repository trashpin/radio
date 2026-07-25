# Compare System (Discovery)

"Compare Similar Species" lets a visitor distinguish look-alikes (e.g.
Red-shouldered Hawk vs Red-tailed / Broad-winged / Cooper's Hawk).

## Data
- **`species_comparisons`** links a base `species_id` to `compare_species_id`
  with `key_differences` and an ordering. Look-alikes for a species = its
  comparison rows.
- Each compared species pulls its own `species` fields for the comparison card:
  photo (`hero_media_id`), size, color, habitat (`species_habitats`), calls
  (`species_sounds`), wing shape / tail shape (fields on `species` or
  `species_facts`).

## UX
- Species detail → **LOOK-ALIKES** section: horizontal list of similar species
  (image + name + "Quick Compare").
- **Compare screen**: a `PageView` of comparison cards the user can **swipe**
  between. Each card shows the base species beside one look-alike with aligned
  rows:
  Photo · Size · Color · Habitat · Calls · Wing Shape · Tail Shape ·
  **Key Differences** (highlighted).
- A **Quick Compare** button on any look-alike opens the Compare screen focused
  on that pair.

## Architecture
```
species_detail_screen → LookAlikes(section) → compare_screen(baseId, [compareIds])
compareProvider(baseId) → species_comparisons + joined species/habitat/sounds
```
Reuses `SupabaseReadRepository`, `MediaRepository` (photos), and the sounds
player. No duplicate models — comparison cards are views over `species`.

## Future
- AI-assisted "what's the difference?" narration (AI Ranger seam).
- Auto-suggest look-alikes from shared category + morphology fields.
