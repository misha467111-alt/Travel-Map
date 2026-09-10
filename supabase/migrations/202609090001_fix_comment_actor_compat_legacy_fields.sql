-- Fix: public.comments has legacy NOT NULL columns (user_id, text) that the
-- authenticated role has no column-level INSERT grant for, and that
-- set_comment_actor_compat() never backfilled on INSERT. This made every
-- authenticated comment insert fail with a not-null violation on user_id.
-- Trigger-internal NEW.* assignments are not subject to the client's
-- column grants, so backfilling them here requires no GRANT/RLS change.
-- All other existing logic of the function is unchanged.

CREATE OR REPLACE FUNCTION public.set_comment_actor_compat()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  if tg_op='INSERT' then
    new.author_id := auth.uid();
    new.user_id := auth.uid();
    new.text := coalesce(new.text, new.body, '');
    new.status := 'visible';
    new.created_at := coalesce(new.created_at, now());
  elsif new.author_id is distinct from old.author_id
     or new.created_at is distinct from old.created_at
     or new.status is distinct from old.status then
    raise exception 'comment system fields are server-managed' using errcode='42501';
  end if;

  new.updated_at := now();
  return new;
end
$function$
;
