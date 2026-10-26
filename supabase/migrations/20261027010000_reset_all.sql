-- 全コート・全試合の得点記録をまとめて消す（本番前のテストデータ削除用）
create or replace function public.reset_all(p_pin text)
returns int language plpgsql security definer set search_path = public, private as $$
declare v_n int;
begin
  if not public.check_pin(p_pin) then raise exception 'PINが違います'; end if;
  delete from public.events where true;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function public.reset_all(text) from public;
grant execute on function public.reset_all(text) to anon, authenticated;
