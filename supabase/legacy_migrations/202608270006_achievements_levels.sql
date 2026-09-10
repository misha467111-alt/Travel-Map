-- Expanded achievements + 5 XP levels with +1 invite per newly unlocked level.
-- Forward-only and safe for the current production schema.

begin;

-- ---------------------------------------------------------------------------
-- 5 LEVELS
-- Tier 1: 0 XP       Новачок
-- Tier 2: 100 XP     Дослідник
-- Tier 3: 300 XP     Мандрівник
-- Tier 4: 600 XP     Турист
-- Tier 5: 1000 XP    Першовідкривач
-- ---------------------------------------------------------------------------

create or replace function public.travel_level_tier(points integer)
returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select case
    when points >= 1000 then 5
    when points >= 600 then 4
    when points >= 300 then 3
    when points >= 100 then 2
    else 1
  end
$$;

create or replace function public.profile_level_for_xp(points integer)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select case
    when points >= 1000 then 'Першовідкривач'
    when points >= 600 then 'Турист'
    when points >= 300 then 'Мандрівник'
    when points >= 100 then 'Дослідник'
    else 'Новачок'
  end
$$;

update public.profiles
set level = public.profile_level_for_xp(greatest(coalesce(xp, 0), 0))
where level is distinct from public.profile_level_for_xp(greatest(coalesce(xp, 0), 0));

alter table public.profiles
  add column if not exists highest_level_rewarded integer not null default 1;

-- If an existing account already has enough XP for a higher tier, grant any
-- missing level invites once and remember the rewarded tier. Re-running the
-- migration is idempotent because highest_level_rewarded moves forward.
update public.profiles
set
  invite_balance = greatest(coalesce(invite_balance, 0), 0)
    + greatest(
        0,
        public.travel_level_tier(greatest(coalesce(xp, 0), 0))
          - greatest(1, least(5, coalesce(highest_level_rewarded, 1)))
      ),
  highest_level_rewarded = greatest(
    greatest(1, least(5, coalesce(highest_level_rewarded, 1))),
    public.travel_level_tier(greatest(coalesce(xp, 0), 0))
  )
where public.travel_level_tier(greatest(coalesce(xp, 0), 0))
      > greatest(1, least(5, coalesce(highest_level_rewarded, 1)));

create or replace function public.award_invite_for_level_unlock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_tier integer;
  rewarded integer;
  gained integer;
begin
  new.xp := greatest(coalesce(new.xp, 0), 0);
  new_tier := public.travel_level_tier(new.xp);
  rewarded := greatest(1, least(5, coalesce(old.highest_level_rewarded, 1)));

  if new_tier > rewarded then
    gained := new_tier - rewarded;
    new.invite_balance := greatest(coalesce(new.invite_balance, 0), 0) + gained;
    new.highest_level_rewarded := new_tier;
  else
    new.highest_level_rewarded := rewarded;
  end if;

  return new;
end
$$;

drop trigger if exists zz_profiles_level_invite_reward on public.profiles;
create trigger zz_profiles_level_invite_reward
before update of xp on public.profiles
for each row
execute function public.award_invite_for_level_unlock();

-- ---------------------------------------------------------------------------
-- ACHIEVEMENT CATALOG
-- ---------------------------------------------------------------------------

create table if not exists public.achievement_definitions (
  achievement_key text primary key,
  name text not null,
  description text not null,
  icon text not null,
  category text not null,
  metric text not null,
  target numeric not null check (target > 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.achievement_definitions enable row level security;

drop policy if exists achievement_definitions_read on public.achievement_definitions;
create policy achievement_definitions_read
on public.achievement_definitions
for select
to authenticated
using (true);

grant select on public.achievement_definitions to authenticated;

create table if not exists public.user_achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_key text not null,
  unlocked_at timestamptz not null default now(),
  unique(user_id, achievement_key)
);

-- Old migrations used a restrictive CHECK with only four keys. Remove only
-- achievement_key CHECK constraints so the catalog can grow without migrations.
do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.user_achievements'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%achievement_key%'
  loop
    execute format('alter table public.user_achievements drop constraint if exists %I', r.conname);
  end loop;
end $$;

alter table public.user_achievements enable row level security;

drop policy if exists user_achievements_read_own on public.user_achievements;
create policy user_achievements_read_own
on public.user_achievements
for select
to authenticated
using (user_id = auth.uid());

grant select on public.user_achievements to authenticated;
revoke insert, update, delete on public.user_achievements from authenticated;

insert into public.achievement_definitions
  (achievement_key, name, description, icon, category, metric, target, sort_order)
values
  -- Locations
  ('location_1',   'Перша мітка',              'Додайте свою першу локацію на карту.',                      'place',        'Локації', 'locations', 1,   10),
  ('location_5',   'Картограф-початківець',    'П’ять власних місць уже формують вашу карту.',               'map',          'Локації', 'locations', 5,   20),
  ('location_10',  'Локальний знавець',        'Додайте 10 перевірених вами локацій.',                        'explore',      'Локації', 'locations', 10,  30),
  ('location_25',  'Мисливець за місцями',     'Знайдіть і додайте 25 цікавих точок.',                        'radar',        'Локації', 'locations', 25,  40),
  ('location_50',  'Картограф',                'Пів сотні локацій — серйозний внесок у Travel Map.',           'public',       'Локації', 'locations', 50,  50),
  ('location_100', 'Легенда карти',             'Додайте 100 локацій.',                                         'emoji_events', 'Локації', 'locations', 100, 60),

  -- Check-ins
  ('checkin_1',    'Я тут!',                    'Зробіть перший підтверджений check-in.',                       'pin',          'Відвідування', 'checkins', 1,   110),
  ('checkin_5',    'Перші кроки',               'Відвідайте 5 місць.',                                          'hiking',       'Відвідування', 'checkins', 5,   120),
  ('checkin_10',   'Мандрівний ритм',           'Зробіть 10 check-in.',                                         'directions',   'Відвідування', 'checkins', 10,  130),
  ('checkin_25',   'Завсідник пригод',          'Відвідайте 25 різних точок.',                                 'flag',         'Відвідування', 'checkins', 25,  140),
  ('checkin_50',   'Невтомний дослідник',       '50 підтверджених відвідувань.',                                'terrain',      'Відвідування', 'checkins', 50,  150),
  ('checkin_100',  'Сотня відкриттів',          'Зробіть 100 check-in.',                                        'workspace',    'Відвідування', 'checkins', 100, 160),

  -- Friends
  ('friends_1',    'Не один',                   'Додайте першого друга.',                                       'person_add',   'Соціальне', 'friends', 1,  210),
  ('friends_5',    'Команда',                   'Зберіть компанію з 5 друзів.',                                 'groups',       'Соціальне', 'friends', 5,  220),
  ('friends_10',   'Душа експедиції',           'Майте 10 підтверджених друзів.',                               'diversity',    'Соціальне', 'friends', 10, 230),
  ('friends_25',   'Мандрівна компанія',        '25 друзів у вашій мережі.',                                    'group_work',   'Соціальне', 'friends', 25, 240),
  ('friends_50',   'Велика експедиція',         '50 друзів у Travel Map.',                                      'hub',          'Соціальне', 'friends', 50, 250),

  -- Photos
  ('photos_1',     'Перший кадр',               'Додайте перше фото локації.',                                  'photo',        'Фото', 'photos', 1,  310),
  ('photos_5',     'Фотослід',                  'Завантажте 5 фото.',                                           'camera',       'Фото', 'photos', 5,  320),
  ('photos_10',    'Колекціонер фото',          'Завантажте 10 фото з мандрів.',                                'collections',  'Фото', 'photos', 10, 330),
  ('photos_25',    'Фотоархів',                 '25 фотографій місць.',                                         'photo_album',  'Фото', 'photos', 25, 340),
  ('photos_50',    'Очі Travel Map',            'Поділіться 50 фотографіями.',                                 'camera_alt',   'Фото', 'photos', 50, 350),

  -- Distance
  ('distance_10',   'Розігрів',                 'Подолайте 10 км у пригодах.',                                  'route',        'Відстань', 'distance', 10,   410),
  ('distance_50',   'За горизонт',              'Подолайте 50 км.',                                             'route',        'Відстань', 'distance', 50,   420),
  ('distance_100',  'Дослідник 100',            'Подолайте 100 км.',                                            'route',        'Відстань', 'distance', 100,  430),
  ('distance_250',  'Дальня дорога',            'Подолайте 250 км.',                                            'travel',       'Відстань', 'distance', 250,  440),
  ('distance_500',  'Півтисячі',                'Подолайте 500 км.',                                            'travel',       'Відстань', 'distance', 500,  450),
  ('distance_1000', 'Тисяча кілометрів',        'Подолайте 1000 км.',                                           'flight',       'Відстань', 'distance', 1000, 460),

  -- Comments
  ('comments_1',   'Перший відгук',             'Залиште перший корисний коментар.',                            'comment',      'Спільнота', 'comments', 1,  510),
  ('comments_10',  'Голос мандрівника',         'Залиште 10 коментарів.',                                       'forum',        'Спільнота', 'comments', 10, 520),
  ('comments_50',  'Місцевий експерт',          'Допоможіть спільноті 50 коментарями.',                         'reviews',      'Спільнота', 'comments', 50, 530),

  -- XP / Levels
  ('level_2',      'Рівень II — Дослідник',     'Досягніть 100 XP та відкрийте другий рівень.',                  'level',        'Рівні', 'xp', 100,  610),
  ('level_3',      'Рівень III — Мандрівник',   'Досягніть 300 XP та відкрийте третій рівень.',                  'level',        'Рівні', 'xp', 300,  620),
  ('level_4',      'Рівень IV — Турист',        'Досягніть 600 XP та відкрийте четвертий рівень.',               'level',        'Рівні', 'xp', 600,  630),
  ('level_5',      'Рівень V — Першовідкривач', 'Досягніть 1000 XP — максимальний рівень.',                      'trophy',       'Рівні', 'xp', 1000, 640)
on conflict (achievement_key) do update set
  name = excluded.name,
  description = excluded.description,
  icon = excluded.icon,
  category = excluded.category,
  metric = excluded.metric,
  target = excluded.target,
  sort_order = excluded.sort_order;

-- Return one metric value for the current user. This is intentionally
-- centralized so both unlocking and UI progress use exactly the same source.
create or replace function public.achievement_metric_value(p_uid uuid, p_metric text)
returns numeric
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  value numeric := 0;
begin
  case p_metric
    when 'locations' then
      if exists (
        select 1 from information_schema.columns
        where table_schema='public' and table_name='locations' and column_name='owner_id'
      ) then
        execute 'select count(*)::numeric from public.locations where owner_id = $1'
          into value using p_uid;
      elsif exists (
        select 1 from information_schema.columns
        where table_schema='public' and table_name='locations' and column_name='user_id'
      ) then
        execute 'select count(*)::numeric from public.locations where user_id = $1'
          into value using p_uid;
      end if;

    when 'checkins' then
      if to_regclass('public.check_ins') is not null then
        execute 'select count(*)::numeric from public.check_ins where user_id = $1'
          into value using p_uid;
      end if;

    when 'friends' then
      if to_regclass('public.friendships') is not null then
        execute $q$
          select count(*)::numeric from public.friendships
          where status = 'accepted' and (user_id_1 = $1 or user_id_2 = $1)
        $q$ into value using p_uid;
      end if;

    when 'photos' then
      if to_regclass('public.location_photos') is not null then
        execute 'select count(*)::numeric from public.location_photos where uploader_id = $1'
          into value using p_uid;
      end if;

    when 'comments' then
      if to_regclass('public.comments') is not null then
        if exists (
          select 1 from information_schema.columns
          where table_schema='public' and table_name='comments' and column_name='author_id'
        ) then
          execute 'select count(*)::numeric from public.comments where author_id = $1'
            into value using p_uid;
        elsif exists (
          select 1 from information_schema.columns
          where table_schema='public' and table_name='comments' and column_name='user_id'
        ) then
          execute 'select count(*)::numeric from public.comments where user_id::text = $1::text'
            into value using p_uid;
        end if;
      end if;

    when 'distance' then
      select coalesce(distance_traveled_km, 0)::numeric
      into value
      from public.profiles
      where id = p_uid;

    when 'xp' then
      select coalesce(xp, 0)::numeric
      into value
      from public.profiles
      where id = p_uid;

    else
      value := 0;
  end case;

  return coalesce(value, 0);
end
$$;

create or replace function public.check_and_unlock_achievements()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  d record;
  progress numeric;
begin
  if uid is null then
    raise exception 'authentication required';
  end if;

  for d in
    select achievement_key, metric, target
    from public.achievement_definitions
  loop
    progress := public.achievement_metric_value(uid, d.metric);
    if progress >= d.target then
      insert into public.user_achievements(user_id, achievement_key)
      values (uid, d.achievement_key)
      on conflict (user_id, achievement_key) do nothing;
    end if;
  end loop;
end
$$;

create or replace function public.get_achievement_progress()
returns table (
  achievement_key text,
  name text,
  description text,
  icon text,
  category text,
  unlock_condition text,
  progress numeric,
  target numeric,
  is_unlocked boolean,
  unlocked_at timestamptz,
  sort_order integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'authentication required';
  end if;

  perform public.check_and_unlock_achievements();

  return query
  select
    d.achievement_key,
    d.name,
    d.description,
    d.icon,
    d.category,
    case d.metric
      when 'locations' then 'Додайте ' || d.target::int || ' локацій'
      when 'checkins' then 'Зробіть ' || d.target::int || ' check-in'
      when 'friends' then 'Додайте ' || d.target::int || ' друзів'
      when 'photos' then 'Додайте ' || d.target::int || ' фото'
      when 'comments' then 'Залиште ' || d.target::int || ' коментарів'
      when 'distance' then 'Подолайте ' || d.target::int || ' км'
      when 'xp' then 'Наберіть ' || d.target::int || ' XP'
      else 'Виконайте умову'
    end,
    public.achievement_metric_value(uid, d.metric),
    d.target,
    ua.id is not null,
    ua.unlocked_at,
    d.sort_order
  from public.achievement_definitions d
  left join public.user_achievements ua
    on ua.user_id = uid and ua.achievement_key = d.achievement_key
  order by d.sort_order, d.achievement_key;
end
$$;

revoke all on function public.travel_level_tier(integer) from public;
revoke all on function public.award_invite_for_level_unlock() from public;
revoke all on function public.achievement_metric_value(uuid, text) from public;
revoke all on function public.check_and_unlock_achievements() from public;
revoke all on function public.get_achievement_progress() from public;

grant execute on function public.check_and_unlock_achievements() to authenticated;
grant execute on function public.get_achievement_progress() to authenticated;

commit;
