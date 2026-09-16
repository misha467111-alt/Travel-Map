// Product Architecture v1.0 Phase 1 (XP correctness): the ONE client-side
// mirror of the backend-authoritative level/XP contract --
// `public.profile_level_for_xp` / `public.travel_level_tier` in
// `supabase/migrations/202608290000_production_canonical_baseline.sql`.
// The backend is authoritative and unchanged by this file: `profiles.level`
// is always server-computed (`set_profile_server_fields`), and this mirror
// exists only so client-side UI (progress bars, "XP to next level" text)
// can present that same 5-level shape without inventing its own thresholds.
// Do not add a second copy of these thresholds elsewhere -- reuse this one.

/// XP floor of each of the exactly 5 levels, in order. Level N's floor is
/// `xpLevelThresholds[N - 1]`; level 5 (index 4) is the maximum level --
/// there is no level 6.
const List<int> xpLevelThresholds = [0, 100, 300, 600, 1000];

/// 1-based level/tier for a given XP total, matching
/// `travel_level_tier(points)` exactly.
int xpLevelTier(int xp) {
  var tier = 1;
  for (var i = 1; i < xpLevelThresholds.length; i++) {
    if (xp >= xpLevelThresholds[i]) tier = i + 1;
  }
  return tier;
}

/// The XP floor of the level `xp` currently falls in.
int xpCurrentLevelFloor(int xp) => xpLevelThresholds[xpLevelTier(xp) - 1];

/// XP required to reach the next level, or `null` if already at the
/// maximum level (5) -- callers must not invent a threshold in that case.
int? xpNextLevelThreshold(int xp) {
  final tier = xpLevelTier(xp);
  if (tier >= xpLevelThresholds.length) return null;
  return xpLevelThresholds[tier];
}

/// Progress (0.0-1.0) within the user's *current* level band -- i.e. how
/// far from this level's floor toward the next level's threshold, not
/// from zero. Always `1.0` at the maximum level.
double xpProgressWithinLevel(int xp) {
  final next = xpNextLevelThreshold(xp);
  if (next == null) return 1;
  final floor = xpCurrentLevelFloor(xp);
  return ((xp - floor) / (next - floor)).clamp(0, 1);
}
