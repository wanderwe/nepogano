-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно.
--
-- "Капсули часу" — лист, запечатаний до обраної дати в майбутньому. Текст
-- недоступний навіть автору до цієї дати. Розбито на дві таблиці навмисно:
-- RLS діє по рядках, не по колонках, тож єдиний спосіб дійсно заборонити
-- читати тільки `body`, лишаючи метадані (для кого лист, коли розкриється)
-- видимими одразу — винести body в окрему таблицю з власною SELECT-політикою,
-- що звіряє unlock_at. Метадані потрібні одразу, щоб у списку показувати
-- 🔒 "розкриється {дата}", не чекаючи самої дати.
--
-- Фаза 1: recipient_id завжди null (лист собі). Колонку й політики під
-- листи другові додано одразу, щоб Фаза 2 не вимагала нової міграції —
-- тільки вибір отримувача в UI.

create table if not exists public.future_letters (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unlock_at timestamptz not null,
  opened_at timestamptz,
  -- Окремо від opened_at: ставиться, щойно отримувач побачив ЗАПЕЧАТАНИЙ
  -- лист у своєму списку (просто факт "хтось мені написав"), а не коли
  -- прочитав текст — це може статись задовго до unlock_at.
  recipient_seen_at timestamptz
);

alter table public.future_letters
  add column if not exists recipient_seen_at timestamptz;

alter table public.future_letters enable row level security;

-- метадані видно обом сторонам одразу (список, банер, read receipt через
-- opened_at) — саме body лишається прихованим окремою таблицею нижче.
drop policy if exists "future_letters_select" on public.future_letters;
create policy "future_letters_select"
on public.future_letters for select
using (author_id = auth.uid() or recipient_id = auth.uid());

-- лист другові можна написати лише прямому другу (той самий
-- friendships-принцип, що й у friend_nudges); лист собі — recipient_id null,
-- нічого додатково перевіряти не треба.
drop policy if exists "future_letters_insert" on public.future_letters;
create policy "future_letters_insert"
on public.future_letters for insert
with check (
  author_id = auth.uid()
  and (
    recipient_id is null
    or exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester_id = auth.uid() and f.addressee_id = recipient_id)
          or (f.addressee_id = auth.uid() and f.requester_id = recipient_id)
        )
    )
  )
);

-- передумати можна, поки не запечатано; редагувати текст — ні (підривало б
-- сенс фічі), тому апдейта на body взагалі нема, лише delete цілого листа.
drop policy if exists "future_letters_delete" on public.future_letters;
create policy "future_letters_delete"
on public.future_letters for delete
using (author_id = auth.uid() or recipient_id = auth.uid());

-- єдине, що можна змінювати — позначка "прочитано", і лише після розкриття.
drop policy if exists "future_letters_update_opened" on public.future_letters;
create policy "future_letters_update_opened"
on public.future_letters for update
using ((author_id = auth.uid() or recipient_id = auth.uid()) and unlock_at <= now())
with check ((author_id = auth.uid() or recipient_id = auth.uid()) and unlock_at <= now());

-- окрема політика для recipient_seen_at — на відміну від opened_at, це
-- можна ставити ще ДО unlock_at (сам факт отримання запечатаного листа).
drop policy if exists "future_letters_update_recipient_seen" on public.future_letters;
create policy "future_letters_update_recipient_seen"
on public.future_letters for update
using (recipient_id = auth.uid())
with check (recipient_id = auth.uid());

create table if not exists public.future_letter_bodies (
  letter_id uuid primary key references public.future_letters(id) on delete cascade,
  body text not null
);

alter table public.future_letter_bodies enable row level security;

-- єдине місце, де насправді перевіряється дата розкриття перед видачею
-- тексту — незалежно від того, звідки прийшов запит.
drop policy if exists "future_letter_bodies_select" on public.future_letter_bodies;
create policy "future_letter_bodies_select"
on public.future_letter_bodies for select
using (
  exists (
    select 1 from public.future_letters fl
    where fl.id = letter_id
      and (fl.author_id = auth.uid() or fl.recipient_id = auth.uid())
      and fl.unlock_at <= now()
  )
);

drop policy if exists "future_letter_bodies_insert" on public.future_letter_bodies;
create policy "future_letter_bodies_insert"
on public.future_letter_bodies for insert
with check (
  exists (
    select 1 from public.future_letters fl
    where fl.id = letter_id and fl.author_id = auth.uid()
  )
);
