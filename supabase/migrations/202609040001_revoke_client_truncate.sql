-- Minimal client-role hardening. TRUNCATE bypasses row-level security and is
-- never required by the Travel Map client. No row CRUD grants are changed.
revoke truncate on table
  public.achievement_definitions,
  public.categories,
  public.check_ins,
  public.comments,
  public.follows,
  public.friendships,
  public.invite_codes,
  public.invite_redemptions,
  public.invites,
  public.location_categories,
  public.location_photos,
  public.location_tags,
  public.locations,
  public.messages,
  public.notifications,
  public.profiles,
  public.reviews,
  public.routes,
  public.tags,
  public.user_achievements,
  public.user_settings
from public, anon, authenticated;
