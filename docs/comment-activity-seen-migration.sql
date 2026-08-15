-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- Переносить мітку "коментар переглянуто" з SharedPreferences (сховище на
-- ПРИСТРІЙ) у БД (сховище на АКАУНТ) — інакше зайшовши з іншого пристрою
-- юзер бачив усі раніше переглянуті коментарі знову як нові: локальне
-- сховище не синхронізується між пристроями. Той самий "множина id, не
-- єдина мітка часу" підхід, що й був у SharedPreferences-версії
-- (comment_activity.dart) — курсор не може коректно відобразити "відкрив
-- другий запис зі списку, а перший так і лишив непрочитаним".

create table public.comment_activity_seen (
  user_id uuid not null references auth.users(id) on delete cascade,
  -- Без FK на конкретну таблицю: id належить або checkin_comments, або
  -- subject_checkin_comments — це union двох джерел, як і в самій стрічці
  -- (comment_activity.dart), окремого спільного батька в схемі нема.
  comment_id uuid not null,
  seen_at timestamptz not null default now(),
  primary key (user_id, comment_id)
);

alter table public.comment_activity_seen enable row level security;

create policy "comment_activity_seen_all"
on public.comment_activity_seen for all
using (user_id = auth.uid())
with check (user_id = auth.uid());
