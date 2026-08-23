// Ocala Forest Explorer v3 -- official USFS trail data import/refresh.
//
// Manually invoked (not cron-scheduled -- this source dataset changes on
// the order of years, not minutes). Fetches the U.S. Forest Service's
// public "National Forest System Trails" ArcGIS REST service
// (EDW_TrailNFSPublish_01), keeps every real trail LineString/MultiLineString
// exactly as the source returns it, upserts it into forest_trail_segments
// (lossless -- one row per raw USFS record), then calls rebuild_forest_trails
// to recompute which segments actually intersect the EXISTING Ocala boundary
// (forest_boundaries.geom, real ST_Intersects -- never a name match) and
// regroup qualifying segments into user-facing forest_trails rows.
//
// Invents nothing: every value written is either a literal USFS-provided
// field, a real aggregate of USFS-provided numbers (length_miles = sum of
// gis_miles, null if none present), or a geometric fact of the USFS
// geometry itself (geometric_start_lat/lng -- explicitly not a trailhead
// facility, since the source has no trailhead layer). Missing source
// fields are stored/left as null, never guessed.
//
// Refresh-safe: import_forest_trail_segment skips the write when the
// incoming content hash matches what's stored, and only ever writes the
// official-sourced columns by name (never `update ... set *`), so any
// future curated columns added to forest_trails are never at risk.
//
// Deploy:
//   supabase functions deploy ocala-trails-import
// Invoke (service-role key as bearer -- this is an admin/maintenance
// action, never called from the Flutter client):
//   POST {SUPABASE_URL}/functions/v1/ocala-trails-import
//   body: {} -- operates on the single existing Ocala National Forest
//   boundary row; there is only one forest in this schema today.

const DEFAULT_SUPABASE_URL = "https://qqeyvhcgirmfokoftiuz.supabase.co";

function resolveBaseUrl(): string {
  const raw = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const url = raw.length > 0 ? raw : DEFAULT_SUPABASE_URL;
  return url.replace(/\/+$/, "");
}

function buildSupabaseUrl(path: string): string {
  return `${resolveBaseUrl()}/${path.replace(/^\/+/, "")}`;
}

// Edge Functions inject SUPABASE_SERVICE_ROLE_KEY; CI passes SUPABASE_SERVICE_KEY.
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_KEY") ?? "";
const SB = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };

const TRAIL_SERVICE_URL =
  "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_TrailNFSPublish_01/MapServer/0/query";
const SOURCE_DATASET = "National Forest System Trails (EDW_TrailNFSPublish_01)";

interface UsfsTrailProps {
  trail_cn?: string | null;
  globalid?: string | null;
  trail_name?: string | null;
  trail_no?: string | null;
  trail_type?: string | null;
  trail_class?: string | null;
  trail_surface?: string | null;
  accessibility_status?: string | null;
  national_trail_designation?: number | null;
  managing_org?: string | null;
  admin_org?: string | null;
  gis_miles?: number | null;
  [key: string]: unknown;
}

interface GeoJsonGeometry {
  type: string;
  coordinates: unknown;
}

interface GeoJsonFeature {
  type: "Feature";
  geometry: GeoJsonGeometry | null;
  properties: UsfsTrailProps;
}

interface GeoJsonFeatureCollection {
  type: "FeatureCollection";
  features?: GeoJsonFeature[];
  error?: unknown;
  exceededTransferLimit?: boolean;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(buildSupabaseUrl(`rest/v1/${path}`), { headers: SB });
  if (!r.ok) {
    throw new Error(`GET ${path} -> ${r.status}: ${(await r.text()).slice(0, 300)}`);
  }
  return r.json();
}

async function sbRpc(fn: string, args: Record<string, unknown>): Promise<any> {
  const r = await fetch(buildSupabaseUrl(`rest/v1/rpc/${fn}`), {
    method: "POST",
    headers: { ...SB, "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  if (!r.ok) {
    throw new Error(`rpc ${fn} -> ${r.status}: ${(await r.text()).slice(0, 500)}`);
  }
  const text = await r.text();
  return text ? JSON.parse(text) : null;
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// The USFS layer's geometryType is esriGeometryPolyline, but individual
// records can come back as either GeoJSON LineString or MultiLineString.
// Every stored segment is normalized to MultiLineString (forest_trail_
// segments.geom's column type) via ST_Multi in import_forest_trail_segment
// -- this function only validates the shape, it never reduces or merges it.
function assertLineGeometry(geometry: GeoJsonGeometry): void {
  if (geometry.type !== "LineString" && geometry.type !== "MultiLineString") {
    throw new Error(`Unexpected trail geometry type: ${geometry.type}`);
  }
}

async function fetchTrailFeatures(
  bbox: { minx: number; miny: number; maxx: number; maxy: number },
): Promise<GeoJsonFeature[]> {
  const params = new URLSearchParams({
    where: "1=1",
    geometry: `${bbox.minx},${bbox.miny},${bbox.maxx},${bbox.maxy}`,
    geometryType: "esriGeometryEnvelope",
    inSR: "4326",
    spatialRel: "esriSpatialRelIntersects",
    outFields: "*",
    outSR: "4326",
    f: "geojson",
  });
  const r = await fetch(`${TRAIL_SERVICE_URL}?${params.toString()}`);
  if (!r.ok) {
    throw new Error(`USFS trail service ${r.status}: ${(await r.text()).slice(0, 300)}`);
  }
  const data = await r.json() as GeoJsonFeatureCollection;
  if (data.error) {
    throw new Error(`USFS trail service error: ${JSON.stringify(data.error).slice(0, 300)}`);
  }
  if (data.exceededTransferLimit) {
    // Disclosed, not silently worked around: the bbox query hit the
    // service's page size and this run only has the first page. A real
    // pagination loop (resultOffset) would be needed if this ever happens
    // for Ocala's bbox -- as of the research behind this import it does not
    // (215 features, well under the service's transfer limit).
    console.error(
      "ocala-trails-import: USFS response set exceededTransferLimit=true -- " +
        "results below are INCOMPLETE; add resultOffset pagination.",
    );
  }
  return data.features ?? [];
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Only POST supported" }, 405);
  if (!SERVICE_KEY) return json({ error: "SUPABASE_SERVICE_ROLE_KEY not set" }, 500);

  try {
    const forests = await sbGet("forest_boundaries?select=id,name&limit=1");
    const forest = forests[0];
    if (!forest) return json({ error: "no forest_boundaries row found" }, 500);

    const bboxRows = await sbRpc("forest_boundary_bbox", { p_forest_id: forest.id });
    const bbox = bboxRows?.[0];
    if (!bbox) return json({ error: "forest_boundary_bbox returned nothing" }, 500);

    const features = await fetchTrailFeatures(bbox);

    let imported = 0;
    let skippedNoGeometry = 0;
    const errors: string[] = [];

    for (const feature of features) {
      if (!feature.geometry) {
        skippedNoGeometry++;
        continue;
      }
      try {
        assertLineGeometry(feature.geometry);
      } catch (err) {
        errors.push(String((err as Error)?.message ?? err));
        continue;
      }

      const props = feature.properties ?? {};
      // trail_cn is NOT unique per record -- it's a "trail common number"
      // shared by every geometry segment belonging to the same logical
      // trail/route (e.g. all 27 segments of Motorcycle Trail 0225 share
      // one trail_cn). globalid is the source's actual per-record unique
      // identifier; objectid is the fallback if it's ever missing. Using
      // trail_cn here was tried first and confirmed wrong empirically (215
      // distinct source features upserted down to 80 rows, silently
      // discarding 135 real segments) before this fix.
      const sourceRecordId = String(
        props.globalid ?? props.objectid ?? "",
      ).trim();
      if (!sourceRecordId) {
        errors.push("feature with no globalid/objectid, skipped");
        continue;
      }

      const geomGeoJson = JSON.stringify(feature.geometry);
      const contentHash = await sha256Hex(
        JSON.stringify({ p: props, g: feature.geometry }),
      );

      await sbRpc("import_forest_trail_segment", {
        p_forest_id: forest.id,
        p_source_record_id: sourceRecordId,
        p_trail_name: props.trail_name ?? null,
        p_trail_no: props.trail_no ?? null,
        p_trail_type: props.trail_type ?? null,
        p_trail_class: props.trail_class ?? null,
        p_trail_surface: props.trail_surface ?? null,
        p_accessibility_status: props.accessibility_status ?? null,
        p_national_trail_designation: props.national_trail_designation ?? null,
        p_managing_org: props.managing_org ?? null,
        p_admin_org: props.admin_org ?? null,
        p_gis_miles: props.gis_miles ?? null,
        p_source_attributes: props,
        p_geom_geojson: geomGeoJson,
        p_content_hash: contentHash,
      });
      imported++;
    }

    await sbRpc("rebuild_forest_trails", { p_forest_id: forest.id });

    const allSegments = await sbGet(
      `forest_trail_segments?forest_id=eq.${forest.id}&select=id`,
    );
    const inForestSegments = await sbGet(
      `forest_trail_segments?forest_id=eq.${forest.id}&in_ocala_forest=eq.true&select=id`,
    );
    const trails = await sbGet(`forest_trails?forest_id=eq.${forest.id}&select=id`);

    return json({
      forest: forest.name,
      source: "U.S. Forest Service",
      sourceDataset: SOURCE_DATASET,
      sourceUrl: TRAIL_SERVICE_URL,
      retrievedFeatureCount: features.length,
      importedOrUpdatedSegments: imported,
      skippedNoGeometry,
      errors,
      totals: {
        segments: allSegments.length,
        segmentsInForest: inForestSegments.length,
        trails: trails.length,
      },
    });
  } catch (err) {
    console.error("ocala-trails-import error", err);
    return json(
      { error: "internal_server_error", detail: String((err as Error)?.message ?? err) },
      500,
    );
  }
});
