-- 個人の測定記録（握力・長座体前屈・腕立て伏せ・バーピー）
create table if not exists public.measurements (
  id         bigserial primary key,
  created_at timestamptz not null default now(),
  game       int  not null,
  court      text not null,
  team       int  not null,
  kind       text not null check (kind in ('grip', 'sitreach', 'pushup', 'burpee')),
  student    int  not null check (student between 1 and 50),
  value      numeric(6,1) not null check (value >= 0 and value < 1000),
  foreign key (game, court, team) references public.matches (game, court, team)
);
alter table public.measurements enable row level security;
drop policy if exists "read measurements" on public.measurements;
create policy "read measurements" on public.measurements for select to anon, authenticated using (true);
revoke insert, update, delete on public.measurements from anon, authenticated;

create or replace function public.add_measure(p_pin text, p_game int, p_court text, p_team int, p_kind text, p_student int, p_value numeric)
returns bigint language plpgsql security definer set search_path = public, private as $$
declare v_id bigint;
begin
  if not public.check_pin(p_pin) then raise exception 'PINが違います'; end if;
  insert into public.measurements (game, court, team, kind, student, value)
  values (p_game, p_court, p_team, p_kind, p_student, p_value) returning id into v_id;
  return v_id;
end $$;

create or replace function public.delete_measure(p_pin text, p_id bigint)
returns bigint language plpgsql security definer set search_path = public, private as $$
begin
  if not public.check_pin(p_pin) then raise exception 'PINが違います'; end if;
  delete from public.measurements where id = p_id;
  return p_id;
end $$;

-- テストデータ削除で、測定記録も一緒に消す
create or replace function public.reset_all(p_pin text)
returns int language plpgsql security definer set search_path = public, private as $$
declare v_n int; v_m int;
begin
  if not public.check_pin(p_pin) then raise exception 'PINが違います'; end if;
  delete from public.events where true;
  get diagnostics v_n = row_count;
  delete from public.measurements where true;
  get diagnostics v_m = row_count;
  return v_n + v_m;
end $$;

revoke all on function public.add_measure(text, int, text, int, text, int, numeric) from public;
revoke all on function public.delete_measure(text, bigint) from public;
grant execute on function public.add_measure(text, int, text, int, text, int, numeric) to anon, authenticated;
grant execute on function public.delete_measure(text, bigint) to anon, authenticated;

do $$ begin
  alter publication supabase_realtime add table public.measurements;
exception when duplicate_object then null; end $$;
