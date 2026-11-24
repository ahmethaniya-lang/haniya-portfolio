-- شغّل هذا الملف مرة وحدة في Supabase: SQL Editor -> New query -> Run
-- Visit analytics for the portfolio. Stores page, country code, device, time on page. No IP addresses.

create table if not exists public.analytics_views (
  id          uuid primary key,
  created_at  timestamptz not null default now(),
  visitor_id  text,
  session_id  text,
  kind        text not null,          -- home | about | category | project
  title       text,
  category    text,
  project_id  text,
  country     text,                   -- 2-letter code e.g. PS
  device      text,                   -- mobile | tablet | desktop
  referrer    text,
  duration    integer not null default 0   -- seconds on the page
);

create index if not exists analytics_views_created_idx on public.analytics_views (created_at desc);

alter table public.analytics_views enable row level security;

-- Only a signed-in admin can read the data. Visitors can't read or write the table directly.
drop policy if exists "admin read analytics" on public.analytics_views;
create policy "admin read analytics" on public.analytics_views
  for select to authenticated using (true);

drop policy if exists "admin delete analytics" on public.analytics_views;
create policy "admin delete analytics" on public.analytics_views
  for delete to authenticated using (true);

-- Visitors write only through these two functions.
create or replace function public.track_view(
  p_id uuid, p_visitor text, p_session text, p_kind text, p_title text,
  p_category text, p_project text, p_country text, p_device text, p_referrer text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_kind not in ('home','about','category','project') then return; end if;
  insert into public.analytics_views
    (id, visitor_id, session_id, kind, title, category, project_id, country, device, referrer)
  values
    (p_id, left(p_visitor,64), left(p_session,64), p_kind, left(p_title,200), left(p_category,200),
     left(p_project,64), left(upper(p_country),2), left(p_device,16), left(p_referrer,200))
  on conflict (id) do nothing;
end $$;

create or replace function public.track_duration(p_id uuid, p_secs integer)
returns void
language sql security definer set search_path = public as $$
  update public.analytics_views
     set duration = greatest(duration, least(coalesce(p_secs,0), 3600))
   where id = p_id;
$$;

revoke all on function public.track_view(uuid,text,text,text,text,text,text,text,text,text) from public;
revoke all on function public.track_duration(uuid,integer) from public;
grant execute on function public.track_view(uuid,text,text,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.track_duration(uuid,integer) to anon, authenticated;
