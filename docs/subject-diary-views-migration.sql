-- Дає можливість показувати "є оновлення" на чіпі щоденника сутності в
-- перемикачі "Я | [сутності] | +" на головному екрані — зараз, якщо
-- співавтор (чи власник) додає новий чек-ін, інший співавтор/власник не
-- дізнається про це, поки сам не зайде саме в цей щоденник і не побачить.
--
-- Два ОКРЕМІ маркери "коли я востаннє бачив", не один — бо головний екран і
-- Історія показують різне:
--   - `last_tab_view_at`: коли перемикав чіп на цю сутність (бачив
--     СЬОГОДНІШНІЙ запис прямо на головному екрані);
--   - `last_history_view_at`: коли відкривав повний календар (`HistoryScreen`)
--     цієї сутності (бачив УСІ дні, не тільки сьогодні).
-- Якщо об'єднати в один timestamp — перегляд сьогоднішнього запису на
-- головному екрані помилково "погасив" би і пропущені старі дні, яких юзер
-- насправді ще не бачив в Історії.
--
-- Ідемпотентно, безпечно виконувати повторно.

create table if not exists public.subject_diary_views (
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  last_tab_view_at timestamptz,
  last_history_view_at timestamptz,
  primary key (user_id, subject_id)
);

alter table public.subject_diary_views enable row level security;

-- Кожен керує лише власним рядком перегляду — і власник сутності, і
-- співавтор дивляться на один і той самий щоденник, але кожен зі своєю
-- окремою позначкою "коли я востаннє бачив".
drop policy if exists "subject_diary_views_own" on public.subject_diary_views;
create policy "subject_diary_views_own"
on public.subject_diary_views for all
using (user_id = auth.uid())
with check (user_id = auth.uid());
