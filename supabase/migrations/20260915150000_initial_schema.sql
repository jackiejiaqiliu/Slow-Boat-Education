begin;

create extension if not exists pgcrypto with schema extensions;

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function public.set_updated_at() from public;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  legal_name text not null check (btrim(legal_name) <> ''),
  username text unique check (username is null or btrim(username) <> ''),
  nccaom_membership_id text check (
    nccaom_membership_id is null or btrim(nccaom_membership_id) <> ''
  ),
  marketing_consent boolean not null default false,
  marketing_consent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not marketing_consent or marketing_consent_at is not null)
);

create table public.series (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (btrim(slug) <> ''),
  title_en text not null check (btrim(title_en) <> ''),
  title_zh text,
  description_en text,
  description_zh text,
  status text not null default 'draft' check (
    status in ('draft', 'published', 'archived')
  ),
  position integer check (position is null or position > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  series_id uuid references public.series (id) on delete set null,
  slug text not null unique check (btrim(slug) <> ''),
  status text not null default 'draft' check (
    status in ('draft', 'published', 'archived')
  ),
  title_en text not null check (btrim(title_en) <> ''),
  title_zh text,
  description_en text,
  description_zh text,
  nccaom_eligible boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  series_id uuid references public.series (id) on delete set null,
  slug text not null unique check (btrim(slug) <> ''),
  product_type text not null check (
    product_type in ('online_course', 'course_bundle', 'workshop')
  ),
  status text not null default 'draft' check (
    status in ('draft', 'active', 'archived')
  ),
  title_en text not null check (btrim(title_en) <> ''),
  title_zh text,
  description_en text,
  description_zh text,
  regular_price_cents integer not null check (regular_price_cents >= 0),
  regular_stripe_price_id text not null unique check (
    btrim(regular_stripe_price_id) <> ''
  ),
  nccaom_price_cents integer check (
    nccaom_price_cents is null or nccaom_price_cents >= 0
  ),
  nccaom_stripe_price_id text unique,
  available_from timestamptz,
  available_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_nccaom_price_pair check (
    (nccaom_price_cents is null and nccaom_stripe_price_id is null)
    or
    (
      nccaom_price_cents is not null
      and nccaom_stripe_price_id is not null
      and btrim(nccaom_stripe_price_id) <> ''
    )
  ),
  constraint products_availability_order check (
    available_until is null
    or available_from is null
    or available_until > available_from
  )
);

create table public.product_course_grants (
  product_id uuid not null references public.products (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete restrict,
  position integer not null check (position > 0),
  created_at timestamptz not null default now(),
  primary key (product_id, course_id),
  unique (product_id, position)
);

create table public.lessons (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete restrict,
  position integer not null check (position > 0),
  slug text not null check (btrim(slug) <> ''),
  title_en text not null check (btrim(title_en) <> ''),
  title_zh text,
  description_en text,
  description_zh text,
  is_required boolean not null default true,
  status text not null default 'draft' check (
    status in ('draft', 'published', 'archived')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (course_id, position),
  unique (course_id, slug)
);

create table public.lesson_media (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lessons (id) on delete restrict,
  language text not null check (language in ('en', 'zh')),
  mux_asset_id text unique,
  mux_playback_id text unique,
  status text not null default 'processing' check (
    status in ('processing', 'ready', 'errored', 'archived')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lesson_id, language)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete restrict,
  status text not null default 'pending' check (
    status in ('pending', 'paid', 'partially_refunded', 'refunded', 'failed')
  ),
  subtotal_cents integer not null check (subtotal_cents >= 0),
  discount_cents integer not null default 0 check (discount_cents >= 0),
  tax_cents integer not null default 0 check (tax_cents >= 0),
  total_cents integer not null check (total_cents >= 0),
  currency text not null default 'usd' check (currency = 'usd'),
  stripe_checkout_session_id text unique,
  stripe_payment_intent_id text unique,
  paid_at timestamptz,
  refunded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint orders_total_matches_components check (
    total_cents = subtotal_cents - discount_cents + tax_cents
  )
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete restrict,
  product_id uuid not null references public.products (id) on delete restrict,
  product_type_snapshot text not null check (
    product_type_snapshot in ('online_course', 'course_bundle', 'workshop')
  ),
  product_title_snapshot text not null check (
    btrim(product_title_snapshot) <> ''
  ),
  price_cents integer not null check (price_cents >= 0),
  stripe_price_id_snapshot text not null check (
    btrim(stripe_price_id_snapshot) <> ''
  ),
  initial_language text check (initial_language in ('en', 'zh')),
  nccaom_credit_selected boolean not null default false,
  nccaom_membership_id_snapshot text,
  created_at timestamptz not null default now(),
  unique (order_id, product_id),
  constraint order_items_nccaom_snapshot check (
    (
      nccaom_credit_selected
      and nccaom_membership_id_snapshot is not null
      and btrim(nccaom_membership_id_snapshot) <> ''
    )
    or
    (
      not nccaom_credit_selected
      and nccaom_membership_id_snapshot is null
    )
  )
);

create table public.order_item_course_grants (
  id uuid primary key default gen_random_uuid(),
  order_item_id uuid not null references public.order_items (id) on delete restrict,
  course_id uuid not null references public.courses (id) on delete restrict,
  course_title_snapshot text not null check (
    btrim(course_title_snapshot) <> ''
  ),
  initial_language text not null check (initial_language in ('en', 'zh')),
  nccaom_credit boolean not null default false,
  nccaom_membership_id_snapshot text,
  created_at timestamptz not null default now(),
  unique (order_item_id, course_id),
  constraint order_item_course_grants_nccaom_snapshot check (
    (
      nccaom_credit
      and nccaom_membership_id_snapshot is not null
      and btrim(nccaom_membership_id_snapshot) <> ''
    )
    or
    (
      not nccaom_credit
      and nccaom_membership_id_snapshot is null
    )
  )
);

create table public.enrollments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete restrict,
  course_id uuid not null references public.courses (id) on delete restrict,
  order_item_course_grant_id uuid not null unique
    references public.order_item_course_grants (id) on delete restrict,
  preferred_language text not null check (preferred_language in ('en', 'zh')),
  nccaom_credit boolean not null default false,
  nccaom_membership_id_snapshot text,
  status text not null default 'active' check (status in ('active', 'revoked')),
  enrolled_at timestamptz not null default now(),
  expires_at timestamptz not null,
  completed_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, course_id),
  constraint enrollments_one_year_access check (
    expires_at = (
      (enrolled_at at time zone 'UTC') + interval '1 year'
    ) at time zone 'UTC'
  ),
  constraint enrollments_nccaom_snapshot check (
    (
      nccaom_credit
      and nccaom_membership_id_snapshot is not null
      and btrim(nccaom_membership_id_snapshot) <> ''
    )
    or
    (
      not nccaom_credit
      and nccaom_membership_id_snapshot is null
    )
  ),
  constraint enrollments_revocation_state check (
    (status = 'active' and revoked_at is null)
    or (status = 'revoked' and revoked_at is not null)
  )
);

create table public.lesson_progress (
  enrollment_id uuid not null references public.enrollments (id) on delete restrict,
  lesson_id uuid not null references public.lessons (id) on delete restrict,
  opened_at timestamptz not null default now(),
  primary key (enrollment_id, lesson_id)
);

create table public.quizzes (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete restrict,
  position integer not null check (position > 0),
  title_en text not null check (btrim(title_en) <> ''),
  title_zh text,
  is_required boolean not null default true,
  passing_percentage integer not null check (
    passing_percentage between 0 and 100
  ),
  status text not null default 'draft' check (
    status in ('draft', 'published', 'archived')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (course_id, position)
);

create table public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quizzes (id) on delete restrict,
  position integer not null check (position > 0),
  prompt_en text not null check (btrim(prompt_en) <> ''),
  prompt_zh text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (quiz_id, position)
);

create table public.quiz_choices (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.quiz_questions (id) on delete restrict,
  position integer not null check (position > 0),
  text_en text not null check (btrim(text_en) <> ''),
  text_zh text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (question_id, position),
  unique (id, question_id)
);

create table public.quiz_answer_keys (
  question_id uuid primary key references public.quiz_questions (id) on delete restrict,
  choice_id uuid not null,
  created_at timestamptz not null default now(),
  foreign key (choice_id, question_id)
    references public.quiz_choices (id, question_id) on delete restrict
);

create table public.quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments (id) on delete restrict,
  quiz_id uuid not null references public.quizzes (id) on delete restrict,
  attempt_number integer not null check (attempt_number > 0),
  correct_count integer not null check (correct_count >= 0),
  question_count integer not null check (question_count > 0),
  score_percentage integer not null check (score_percentage between 0 and 100),
  passed boolean not null,
  submitted_at timestamptz not null default now(),
  unique (enrollment_id, quiz_id, attempt_number),
  check (correct_count <= question_count)
);

create table public.quiz_attempt_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.quiz_attempts (id) on delete restrict,
  question_id uuid not null references public.quiz_questions (id) on delete restrict,
  selected_choice_id uuid not null,
  is_correct boolean not null,
  unique (attempt_id, question_id),
  foreign key (selected_choice_id, question_id)
    references public.quiz_choices (id, question_id) on delete restrict
);

create table public.certificates (
  id uuid primary key default gen_random_uuid(),
  certificate_id uuid not null unique default gen_random_uuid(),
  enrollment_id uuid not null unique references public.enrollments (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  course_id uuid not null references public.courses (id) on delete restrict,
  legal_name_snapshot text not null check (btrim(legal_name_snapshot) <> ''),
  course_title_snapshot text not null check (btrim(course_title_snapshot) <> ''),
  nccaom_credit boolean not null default false,
  nccaom_membership_id_snapshot text,
  issued_at timestamptz not null default now(),
  revoked_at timestamptz,
  revocation_reason text,
  constraint certificates_nccaom_snapshot check (
    (
      nccaom_credit
      and nccaom_membership_id_snapshot is not null
      and btrim(nccaom_membership_id_snapshot) <> ''
    )
    or
    (
      not nccaom_credit
      and nccaom_membership_id_snapshot is null
    )
  ),
  constraint certificates_revocation_state check (
    revoked_at is not null or revocation_reason is null
  )
);

create table public.workshops (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null unique references public.products (id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz,
  timezone text not null check (btrim(timezone) <> ''),
  location_text text,
  capacity integer check (capacity is null or capacity > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);

create table public.workshop_registrations (
  id uuid primary key default gen_random_uuid(),
  workshop_id uuid not null references public.workshops (id) on delete restrict,
  order_item_id uuid not null unique references public.order_items (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  attendee_legal_name_snapshot text not null check (
    btrim(attendee_legal_name_snapshot) <> ''
  ),
  attendee_email_snapshot text not null check (
    btrim(attendee_email_snapshot) <> ''
  ),
  status text not null default 'registered' check (
    status in ('registered', 'cancelled', 'refunded')
  ),
  registered_at timestamptz not null default now(),
  cancelled_at timestamptz,
  constraint workshop_registrations_cancellation_state check (
    (status = 'registered' and cancelled_at is null)
    or (status in ('cancelled', 'refunded') and cancelled_at is not null)
  )
);

create table public.refunds (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete restrict,
  stripe_refund_id text not null unique check (btrim(stripe_refund_id) <> ''),
  status text not null check (
    status in ('pending', 'succeeded', 'failed', 'cancelled')
  ),
  amount_cents integer not null check (amount_cents > 0),
  reason text,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

create table public.refund_items (
  refund_id uuid not null references public.refunds (id) on delete restrict,
  order_item_id uuid not null references public.order_items (id) on delete restrict,
  amount_cents integer not null check (amount_cents > 0),
  primary key (refund_id, order_item_id)
);

create table public.playback_sessions (
  id uuid primary key default gen_random_uuid(),
  watermark_session_id uuid not null unique default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete restrict,
  enrollment_id uuid not null references public.enrollments (id) on delete restrict,
  course_id uuid not null references public.courses (id) on delete restrict,
  lesson_id uuid not null references public.lessons (id) on delete restrict,
  language text not null check (language in ('en', 'zh')),
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  check (expires_at is null or expires_at > created_at)
);

create table public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  stripe_event_id text not null unique check (btrim(stripe_event_id) <> ''),
  event_type text not null check (btrim(event_type) <> ''),
  status text not null default 'received' check (
    status in ('received', 'processed', 'failed')
  ),
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  last_error text
);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger series_set_updated_at
before update on public.series
for each row execute function public.set_updated_at();

create trigger courses_set_updated_at
before update on public.courses
for each row execute function public.set_updated_at();

create trigger products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();

create trigger lessons_set_updated_at
before update on public.lessons
for each row execute function public.set_updated_at();

create trigger lesson_media_set_updated_at
before update on public.lesson_media
for each row execute function public.set_updated_at();

create trigger orders_set_updated_at
before update on public.orders
for each row execute function public.set_updated_at();

create trigger enrollments_set_updated_at
before update on public.enrollments
for each row execute function public.set_updated_at();

create trigger quizzes_set_updated_at
before update on public.quizzes
for each row execute function public.set_updated_at();

create trigger quiz_questions_set_updated_at
before update on public.quiz_questions
for each row execute function public.set_updated_at();

create trigger quiz_choices_set_updated_at
before update on public.quiz_choices
for each row execute function public.set_updated_at();

create trigger workshops_set_updated_at
before update on public.workshops
for each row execute function public.set_updated_at();

create index courses_series_id_idx on public.courses (series_id);
create index courses_status_idx on public.courses (status);
create index products_series_id_idx on public.products (series_id);
create index products_catalog_idx on public.products (status, available_from, available_until);
create index product_course_grants_course_id_idx
  on public.product_course_grants (course_id);
create index lessons_course_status_position_idx
  on public.lessons (course_id, status, position);
create index lesson_media_lesson_status_idx
  on public.lesson_media (lesson_id, status);
create index orders_user_created_at_idx on public.orders (user_id, created_at desc);
create index orders_status_created_at_idx on public.orders (status, created_at);
create index order_items_product_id_idx on public.order_items (product_id);
create index order_item_course_grants_course_id_idx
  on public.order_item_course_grants (course_id);
create index enrollments_user_status_expires_at_idx
  on public.enrollments (user_id, status, expires_at);
create index enrollments_course_id_idx on public.enrollments (course_id);
create index lesson_progress_lesson_id_idx on public.lesson_progress (lesson_id);
create index quizzes_course_status_position_idx
  on public.quizzes (course_id, status, position);
create index quiz_attempt_answers_attempt_id_idx
  on public.quiz_attempt_answers (attempt_id);
create index certificates_user_issued_at_idx
  on public.certificates (user_id, issued_at desc);
create index certificates_course_id_idx on public.certificates (course_id);
create index workshops_starts_at_idx on public.workshops (starts_at);
create index workshop_registrations_user_id_idx
  on public.workshop_registrations (user_id, registered_at desc);
create index workshop_registrations_workshop_id_idx
  on public.workshop_registrations (workshop_id, registered_at);
create index refunds_order_id_idx on public.refunds (order_id, created_at desc);
create index refund_items_order_item_id_idx on public.refund_items (order_item_id);
create index playback_sessions_user_created_at_idx
  on public.playback_sessions (user_id, created_at desc);
create index playback_sessions_enrollment_created_at_idx
  on public.playback_sessions (enrollment_id, created_at desc);
create index playback_sessions_expires_at_idx on public.playback_sessions (expires_at);
create index webhook_events_status_received_at_idx
  on public.webhook_events (status, received_at);

alter table public.profiles enable row level security;
alter table public.series enable row level security;
alter table public.courses enable row level security;
alter table public.products enable row level security;
alter table public.product_course_grants enable row level security;
alter table public.lessons enable row level security;
alter table public.lesson_media enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_item_course_grants enable row level security;
alter table public.enrollments enable row level security;
alter table public.lesson_progress enable row level security;
alter table public.quizzes enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.quiz_choices enable row level security;
alter table public.quiz_answer_keys enable row level security;
alter table public.quiz_attempts enable row level security;
alter table public.quiz_attempt_answers enable row level security;
alter table public.certificates enable row level security;
alter table public.workshops enable row level security;
alter table public.workshop_registrations enable row level security;
alter table public.refunds enable row level security;
alter table public.refund_items enable row level security;
alter table public.playback_sessions enable row level security;
alter table public.webhook_events enable row level security;

create policy "Public can view published series"
on public.series for select
to anon, authenticated
using (status = 'published');

create policy "Public can view active products"
on public.products for select
to anon, authenticated
using (
  status = 'active'
  and (available_from is null or available_from <= now())
  and (available_until is null or available_until > now())
);

create policy "Public can view published courses"
on public.courses for select
to anon, authenticated
using (status = 'published');

create policy "Active learners can view enrolled courses"
on public.courses for select
to authenticated
using (
  exists (
    select 1
    from public.enrollments
    where enrollments.course_id = courses.id
      and enrollments.user_id = (select auth.uid())
      and enrollments.status = 'active'
      and enrollments.expires_at > now()
  )
);

create policy "Public can view active product course grants"
on public.product_course_grants for select
to anon, authenticated
using (
  exists (
    select 1
    from public.products
    where products.id = product_course_grants.product_id
      and products.status = 'active'
      and (products.available_from is null or products.available_from <= now())
      and (products.available_until is null or products.available_until > now())
  )
  and exists (
    select 1
    from public.courses
    where courses.id = product_course_grants.course_id
      and courses.status = 'published'
  )
);

create policy "Public can view published lesson previews"
on public.lessons for select
to anon, authenticated
using (
  status = 'published'
  and exists (
    select 1
    from public.courses
    where courses.id = lessons.course_id
      and courses.status = 'published'
  )
);

create policy "Active learners can view enrolled lessons"
on public.lessons for select
to authenticated
using (
  status = 'published'
  and exists (
    select 1
    from public.enrollments
    where enrollments.course_id = lessons.course_id
      and enrollments.user_id = (select auth.uid())
      and enrollments.status = 'active'
      and enrollments.expires_at > now()
  )
);

create policy "Public can view available workshops"
on public.workshops for select
to anon, authenticated
using (
  exists (
    select 1
    from public.products
    where products.id = workshops.product_id
      and products.status = 'active'
      and (products.available_from is null or products.available_from <= now())
      and (products.available_until is null or products.available_until > now())
  )
);

create policy "Learners can view own profile"
on public.profiles for select
to authenticated
using (id = (select auth.uid()));

create policy "Learners can update own profile"
on public.profiles for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy "Learners can view own orders"
on public.orders for select
to authenticated
using (user_id = (select auth.uid()));

create policy "Learners can view own order items"
on public.order_items for select
to authenticated
using (
  exists (
    select 1
    from public.orders
    where orders.id = order_items.order_id
      and orders.user_id = (select auth.uid())
  )
);

create policy "Learners can view own purchased course grants"
on public.order_item_course_grants for select
to authenticated
using (
  exists (
    select 1
    from public.order_items
    join public.orders on orders.id = order_items.order_id
    where order_items.id = order_item_course_grants.order_item_id
      and orders.user_id = (select auth.uid())
  )
);

create policy "Learners can view own enrollments"
on public.enrollments for select
to authenticated
using (user_id = (select auth.uid()));

create policy "Learners can view own lesson progress"
on public.lesson_progress for select
to authenticated
using (
  exists (
    select 1
    from public.enrollments
    where enrollments.id = lesson_progress.enrollment_id
      and enrollments.user_id = (select auth.uid())
  )
);

create policy "Active learners can view enrolled quizzes"
on public.quizzes for select
to authenticated
using (
  status = 'published'
  and exists (
    select 1
    from public.enrollments
    where enrollments.course_id = quizzes.course_id
      and enrollments.user_id = (select auth.uid())
      and enrollments.status = 'active'
      and enrollments.expires_at > now()
  )
);

create policy "Active learners can view enrolled quiz questions"
on public.quiz_questions for select
to authenticated
using (
  exists (
    select 1
    from public.quizzes
    join public.enrollments on enrollments.course_id = quizzes.course_id
    where quizzes.id = quiz_questions.quiz_id
      and quizzes.status = 'published'
      and enrollments.user_id = (select auth.uid())
      and enrollments.status = 'active'
      and enrollments.expires_at > now()
  )
);

create policy "Active learners can view enrolled quiz choices"
on public.quiz_choices for select
to authenticated
using (
  exists (
    select 1
    from public.quiz_questions
    join public.quizzes on quizzes.id = quiz_questions.quiz_id
    join public.enrollments on enrollments.course_id = quizzes.course_id
    where quiz_questions.id = quiz_choices.question_id
      and quizzes.status = 'published'
      and enrollments.user_id = (select auth.uid())
      and enrollments.status = 'active'
      and enrollments.expires_at > now()
  )
);

create policy "Learners can view own quiz attempts"
on public.quiz_attempts for select
to authenticated
using (
  exists (
    select 1
    from public.enrollments
    where enrollments.id = quiz_attempts.enrollment_id
      and enrollments.user_id = (select auth.uid())
  )
);

create policy "Learners can view own quiz attempt answers"
on public.quiz_attempt_answers for select
to authenticated
using (
  exists (
    select 1
    from public.quiz_attempts
    join public.enrollments on enrollments.id = quiz_attempts.enrollment_id
    where quiz_attempts.id = quiz_attempt_answers.attempt_id
      and enrollments.user_id = (select auth.uid())
  )
);

create policy "Learners can view own certificates"
on public.certificates for select
to authenticated
using (user_id = (select auth.uid()));

create policy "Learners can view own workshop registrations"
on public.workshop_registrations for select
to authenticated
using (user_id = (select auth.uid()));

revoke all on table
  public.profiles,
  public.series,
  public.courses,
  public.products,
  public.product_course_grants,
  public.lessons,
  public.lesson_media,
  public.orders,
  public.order_items,
  public.order_item_course_grants,
  public.enrollments,
  public.lesson_progress,
  public.quizzes,
  public.quiz_questions,
  public.quiz_choices,
  public.quiz_answer_keys,
  public.quiz_attempts,
  public.quiz_attempt_answers,
  public.certificates,
  public.workshops,
  public.workshop_registrations,
  public.refunds,
  public.refund_items,
  public.playback_sessions,
  public.webhook_events
from anon, authenticated;

grant usage on schema public to anon, authenticated, service_role;

grant select on public.series to anon, authenticated;
grant select (
  id,
  series_id,
  slug,
  product_type,
  status,
  title_en,
  title_zh,
  description_en,
  description_zh,
  regular_price_cents,
  nccaom_price_cents,
  available_from,
  available_until,
  created_at,
  updated_at
) on public.products to anon, authenticated;
grant select on public.courses to anon, authenticated;
grant select on public.product_course_grants to anon, authenticated;
grant select on public.lessons to anon, authenticated;
grant select on public.workshops to anon, authenticated;

grant select on public.profiles to authenticated;
grant update (
  legal_name,
  username,
  nccaom_membership_id,
  marketing_consent,
  marketing_consent_at,
  updated_at
) on public.profiles to authenticated;
grant select (
  id,
  user_id,
  status,
  subtotal_cents,
  discount_cents,
  tax_cents,
  total_cents,
  currency,
  paid_at,
  refunded_at,
  created_at,
  updated_at
) on public.orders to authenticated;
grant select (
  id,
  order_id,
  product_id,
  product_type_snapshot,
  product_title_snapshot,
  price_cents,
  initial_language,
  nccaom_credit_selected,
  nccaom_membership_id_snapshot,
  created_at
) on public.order_items to authenticated;
grant select on public.order_item_course_grants to authenticated;
grant select on public.enrollments to authenticated;
grant select on public.lesson_progress to authenticated;
grant select on public.quizzes to authenticated;
grant select on public.quiz_questions to authenticated;
grant select on public.quiz_choices to authenticated;
grant select on public.quiz_attempts to authenticated;
grant select on public.quiz_attempt_answers to authenticated;
grant select on public.certificates to authenticated;
grant select on public.workshop_registrations to authenticated;

grant all on table
  public.profiles,
  public.series,
  public.courses,
  public.products,
  public.product_course_grants,
  public.lessons,
  public.lesson_media,
  public.orders,
  public.order_items,
  public.order_item_course_grants,
  public.enrollments,
  public.lesson_progress,
  public.quizzes,
  public.quiz_questions,
  public.quiz_choices,
  public.quiz_answer_keys,
  public.quiz_attempts,
  public.quiz_attempt_answers,
  public.certificates,
  public.workshops,
  public.workshop_registrations,
  public.refunds,
  public.refund_items,
  public.playback_sessions,
  public.webhook_events
to service_role;

commit;
