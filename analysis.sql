-- ============================================================
-- スポーツ神経衰弱 試合データ分析用SQL（最終報告書用）
-- Supabase の SQL Editor で、使いたいクエリを1つずつ選んで実行してください。
-- 結果は右上の「Export」→ CSV でダウンロードでき、Excel でグラフにできます。
-- ============================================================


-- ------------------------------------------------------------
-- ① 各試合・各コートの最終得点と得点差（接戦だったか）
-- ------------------------------------------------------------
with s as (
  select m.game, m.court, m.team, coalesce(sum(e.points), 0) as pts
  from public.matches m
  left join public.events e on e.game = m.game and e.court = m.court and e.team = m.team
  group by m.game, m.court, m.team
)
select game as 試合, court as コート,
       string_agg('チーム' || team || '：' || pts || '点', '　' order by team) as 得点,
       max(pts) - min(pts) as 得点差
from s
group by game, court
order by game, court;


-- ------------------------------------------------------------
-- ② リードが入れかわった回数と、勝ったチームの最大ビハインド（逆転があったか）
--    リード交代：同点をはさんでも、リードしているチームが変わったら1回と数える
-- ------------------------------------------------------------
with pairs as (
  select game, court, min(team) as a, max(team) as b from public.matches group by game, court
),
run as (
  select e.game, e.court, e.id, p.a, p.b,
         sum(case when e.team = p.a then e.points else -e.points end)
           over (partition by e.game, e.court order by e.id) as diff   -- プラスならチームa がリード
  from public.events e join pairs p using (game, court)
),
lead as (
  select game, court, id, sign(diff) as s from run where diff <> 0
),
changes as (
  select game, court, count(*) filter (where s <> prev) as lead_changes
  from (select game, court, s, lag(s) over (partition by game, court order by id) as prev from lead) x
  group by game, court
),
final as (
  select distinct on (game, court) game, court, a, b, diff from run order by game, court, id desc
),
swing as (
  select r.game, r.court,
         case when f.diff > 0 then -min(r.diff) when f.diff < 0 then max(r.diff) else null end as max_behind
  from run r join final f using (game, court)
  group by r.game, r.court, f.diff
)
select p.game as 試合, p.court as コート,
       coalesce(c.lead_changes, 0) as リード交代回数,
       case when f.diff > 0 then 'チーム' || p.a when f.diff < 0 then 'チーム' || p.b else '引き分け' end as 勝ったチーム,
       greatest(coalesce(s.max_behind, 0), 0) as 勝ったチームの最大ビハインド
from pairs p
left join changes c using (game, court)
left join final f using (game, court)
left join swing s using (game, court)
order by p.game, p.court;


-- ------------------------------------------------------------
-- ③ ラスト6分（2倍）の効果：お題の点のうち、2倍の時間に入った割合
-- ------------------------------------------------------------
select game as 試合, court as コート,
       sum(points) as 総得点,
       sum(points) filter (where kind = 'clear')               as お題の点,
       sum(points) filter (where doubled)                      as 二倍の時間のお題の点,
       round(100.0 * coalesce(sum(points) filter (where doubled), 0)
             / nullif(sum(points) filter (where kind = 'clear'), 0), 1) as 二倍の割合_パーセント
from public.events
group by game, court
order by game, court;


-- ------------------------------------------------------------
-- ④ チームごとの内訳（ペアとお題、どちらで点を取ったか）
-- ------------------------------------------------------------
select team as チーム,
       count(*) filter (where kind = 'pair')  as ペア成立数,
       count(*) filter (where kind = 'clear') as お題クリア数,
       coalesce(sum(points) filter (where kind = 'pair'), 0)  as ペアの点,
       coalesce(sum(points) filter (where kind = 'clear'), 0) as お題の点,
       coalesce(sum(points), 0) as 合計
from generate_series(1, 8) t(team)
left join public.events e using (team)
group by team
order by 合計 desc, お題クリア数 desc, ペア成立数 desc;


-- ------------------------------------------------------------
-- ⑤ 得点の時間変化（グラフ用）：各コートの経過時間ごとの累計得点
--    経過時間は、そのコート・その試合の最初の記録からの分数
--    CSV にして Excel で「経過分」を横軸、「累計得点」を縦軸にすると、逆転の様子が見える
-- ------------------------------------------------------------
select game as 試合, court as コート, team as チーム,
       round(extract(epoch from created_at - min(created_at) over (partition by game, court)) / 60.0, 1) as 経過分,
       kind as 種類, points as 点,
       sum(points) over (partition by game, court, team order by id) as 累計得点
from public.events
order by game, court, id;


-- ------------------------------------------------------------
-- ⑥ 全体のまとめ（報告書の冒頭に書く数字）
-- ------------------------------------------------------------
select count(*)                                   as 記録の総数,
       count(*) filter (where kind = 'pair')      as ペア成立の総数,
       count(*) filter (where kind = 'clear')     as お題クリアの総数,
       sum(points)                                as 全チームの総得点
from public.events;

