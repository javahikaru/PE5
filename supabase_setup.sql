-- スポーツ神経衰弱 スコアボード用のデータベース設定
-- Supabase の「SQL Editor」に全部貼り付けて「Run」を押してください。
-- 1行目の PIN（'0000' の部分）は、GMだけが知る4桁などに必ず変えてください。

-- ===== GM用PIN（外からは読めない場所に保存） =====
create schema if not exists private;
create table if not exists private.settings (key text primary key, value text not null);
insert into private.settings (key, value) values ('pin', '0000')
  on conflict (key) do update set value = excluded.value;

-- ===== 対戦表（試合・コート・チーム） =====
create table if not exists public.matches (
  game  int  not null check (game in (1, 2)),
  court text not null check (court in ('A', 'B', 'C', 'D')),
  team  int  not null check (team between 1 and 8),
  primary key (game, court, team)
);
insert into public.matches (game, court, team) values
  (1,'A',1),(1,'A',2),(1,'B',3),(1,'B',4),(1,'C',5),(1,'C',6),(1,'D',7),(1,'D',8),
  (2,'A',5),(2,'A',8),(2,'B',6),(2,'B',7),(2,'C',1),(2,'C',4),(2,'D',2),(2,'D',3)
  on conflict do nothing;

-- ===== 得点の記録（1回押すごとに1行） =====
create table if not exists public.events (
  id         bigserial primary key,
  created_at timestamptz not null default now(),
  game       int  not null,
  court      text not null,
  team       int  not null,
  kind       text not null check (kind in ('pair', 'clear')),
  points     int  not null check (points in (1, 2, 3)),
  doubled    boolean not null default false,
  foreign key (game, court, team) references public.matches (game, court, team)
);

-- 誰でも「読む」ことはできるが、書き込みは下の関数（PINつき）からだけ
alter table public.matches enable row level security;
alter table public.events  enable row level security;
drop policy if exists "read matches" on public.matches;
drop policy if exists "read events"  on public.events;
create policy "read matches" on public.matches for select to anon, authenticated using (true);
create policy "read events"  on public.events  for select to anon, authenticated using (true);
revoke insert, update, delete on public.events  from anon, authenticated;
revoke insert, update, delete on public.matches from anon, authenticated;

-- ===== GMが使う関数 =====
create or replace function public.check_pin(p_pin text) returns boolean
language sql security definer set search_path = public, private as $$
  select p_pin = (select value from private.settings where key = 'pin');
$$;

create or replace function public.add_event(p_pin text, p_game int, p_court text, p_team int, p_kind text, p_doubled boolean)
returns bigint language plpgsql security definer set search_path = public, private as $$
declare v_id bigint;
begin
  if not public.check_pin(p_pin) then raise exception 'PINが違います'; end if;
  insert into public.events (game, court, team, kind, points, doubled)
  values (p_game, p_court, p_team, p_kind,
          case when p_kind = 'pair' then 3 when p_doubled then 2 else 1 end,
          p_kind = 'clear' and p_doubled)
  returning id into v_id;
  return v_id;
end $$;

-- そのコート・その試合の最後の1件を取り消す
create or replace function public.undo_last(p_pin text, p_game int, p_court text)
returns bigint language plpgsql security definer set search_path = public, private as $$
declare v_id bigint;
begin
  if not public.check_pin(p_pin) then raise exception 'PINが違います'; end if;
  delete from public.events
   where id = (select max(id) from public.events where game = p_game and court = p_court)
  returning id into v_id;
  return v_id;
end $$;

-- そのコート・その試合の記録を全部消す（リハーサル後などに使う）
create or replace function public.reset_court(p_pin text, p_game int, p_court text)
returns int language plpgsql security definer set search_path = public, private as $$
declare v_n int;
begin
  if not public.check_pin(p_pin) then raise exception 'PINが違います'; end if;
  delete from public.events where game = p_game and court = p_court;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

revoke all on function public.check_pin(text) from public;
revoke all on function public.add_event(text, int, text, int, text, boolean) from public;
revoke all on function public.undo_last(text, int, text) from public;
revoke all on function public.reset_court(text, int, text) from public;
grant execute on function public.check_pin(text) to anon, authenticated;
grant execute on function public.add_event(text, int, text, int, text, boolean) to anon, authenticated;
grant execute on function public.undo_last(text, int, text) to anon, authenticated;
grant execute on function public.reset_court(text, int, text) to anon, authenticated;

-- ===== チームごとの集計（第1試合・第2試合・合計） =====
create or replace view public.team_results as
select t.team,
  coalesce(sum(e.points) filter (where e.game = 1), 0)::int        as pts1,
  (count(*) filter (where e.game = 1 and e.kind = 'clear'))::int   as clears1,
  (count(*) filter (where e.game = 1 and e.kind = 'pair'))::int    as pairs1,
  coalesce(sum(e.points) filter (where e.game = 2), 0)::int        as pts2,
  (count(*) filter (where e.game = 2 and e.kind = 'clear'))::int   as clears2,
  (count(*) filter (where e.game = 2 and e.kind = 'pair'))::int    as pairs2,
  coalesce(sum(e.points), 0)::int                                  as total,
  (count(*) filter (where e.kind = 'clear'))::int                  as clears,
  (count(*) filter (where e.kind = 'pair'))::int                   as pairs
from generate_series(1, 8) as t(team)
left join public.events e on e.team = t.team
group by t.team;
grant select on public.team_results to anon, authenticated;

-- ===== 画面へのリアルタイム反映 =====
do $$ begin
  alter publication supabase_realtime add table public.events;
exception when duplicate_object then null; end $$;

-- 全部の記録を消したいとき（本番前のテスト後など）は、次の1行だけを実行:
-- truncate public.events restart identity;
