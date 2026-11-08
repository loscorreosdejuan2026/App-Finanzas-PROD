-- App Finanzas — esquema completo (incluye icono + orden de categorías)

create table categorias (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nombre text not null,
  tipo text not null check (tipo in ('ingreso', 'egreso')),
  icono text,
  orden integer,
  color text,
  created_at timestamptz not null default now()
);

create table descripciones_frecuentes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  categoria_id uuid not null references categorias(id) on delete cascade,
  texto text not null,
  orden integer,
  created_at timestamptz not null default now()
);

create table movimientos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  fecha date not null default current_date,
  categoria_id uuid references categorias(id) on delete set null,
  monto numeric not null check (monto > 0),
  descripcion text,
  es_retiro boolean not null default false,
  es_retiro_extra boolean not null default false,
  monto_usd numeric,
  created_at timestamptz not null default now()
);

alter table categorias enable row level security;
alter table descripciones_frecuentes enable row level security;
alter table movimientos enable row level security;

create policy "descripciones_frecuentes: select propias" on descripciones_frecuentes
  for select using (auth.uid() = user_id);
create policy "descripciones_frecuentes: insert propias" on descripciones_frecuentes
  for insert with check (auth.uid() = user_id);
create policy "descripciones_frecuentes: update propias" on descripciones_frecuentes
  for update using (auth.uid() = user_id);
create policy "descripciones_frecuentes: delete propias" on descripciones_frecuentes
  for delete using (auth.uid() = user_id);

create policy "categorias: select propias" on categorias
  for select using (auth.uid() = user_id);
create policy "categorias: insert propias" on categorias
  for insert with check (auth.uid() = user_id);
create policy "categorias: update propias" on categorias
  for update using (auth.uid() = user_id);
create policy "categorias: delete propias" on categorias
  for delete using (auth.uid() = user_id);

create policy "movimientos: select propios" on movimientos
  for select using (auth.uid() = user_id);
create policy "movimientos: insert propios" on movimientos
  for insert with check (auth.uid() = user_id);
create policy "movimientos: update propios" on movimientos
  for update using (auth.uid() = user_id);
create policy "movimientos: delete propios" on movimientos
  for delete using (auth.uid() = user_id);

-- ============================================================
-- MIGRACIONES APLICADAS (histórico, no hace falta re-correrlas
-- si la tabla ya se creó con el CREATE TABLE de arriba)
-- ============================================================

-- 21/07/2026 — se agregaron columnas icono y orden a categorias
-- (para la grilla de íconos y el reordenamiento con ▲▼)
alter table categorias add column if not exists icono text;
alter table categorias add column if not exists orden integer;

-- 26/07/2026 — descripciones precargadas por categoría (tabla propia con FK a
-- categorias, solo texto + orden manual). Son sugerencias para completar el campo
-- "descripcion" de movimientos (que sigue siendo texto libre) — NO hay columna nueva
-- en movimientos, no hace falta FK ahí. Correr esto si el proyecto ya existía antes
-- de esta fecha (si es un proyecto nuevo, el CREATE TABLE de arriba ya la incluye):
create table if not exists descripciones_frecuentes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  categoria_id uuid not null references categorias(id) on delete cascade,
  texto text not null,
  orden integer,
  created_at timestamptz not null default now()
);
alter table descripciones_frecuentes enable row level security;
-- CREATE POLICY no soporta IF NOT EXISTS: si esta migración ya corrió antes,
-- comentar estas 8 líneas o hacer DROP POLICY primero para poder re-ejecutar.
create policy "descripciones_frecuentes: select propias" on descripciones_frecuentes
  for select using (auth.uid() = user_id);
create policy "descripciones_frecuentes: insert propias" on descripciones_frecuentes
  for insert with check (auth.uid() = user_id);
create policy "descripciones_frecuentes: update propias" on descripciones_frecuentes
  for update using (auth.uid() = user_id);
create policy "descripciones_frecuentes: delete propias" on descripciones_frecuentes
  for delete using (auth.uid() = user_id);

-- 28/07/2026 — marca de "retiro" en movimientos de la categoría AHORROS (Gasto).
-- Sin categoría nueva para retiros: un aporte y un retiro de ahorro son los dos
-- Gasto > AHORROS, y este flag distingue si ese monto se debe sumar o restar del
-- acumulado en la vista "Mis Ahorros". No aplica a ninguna otra categoría.
alter table movimientos add column if not exists es_retiro boolean not null default false;

-- 28/07/2026 — marca de "retiro extra" (compras/pagos grandes que impactan de lleno
-- en el acumulado histórico de AHORROS, ej. remodelación) separada de un "retiro"
-- chico de ajuste mensual. Solo tiene sentido junto con es_retiro = true. Se excluye
-- del Balance/Resumen general (a diferencia de un retiro normal, que sí resta ahí) —
-- solo se ve en la vista "Mis Ahorros".
alter table movimientos add column if not exists es_retiro_extra boolean not null default false;

-- 29/07/2026 — monto en U$D real para movimientos de AHORROS en esa moneda. "monto"
-- sigue siendo siempre en pesos (lo único que toca el Balance general); monto_usd
-- guarda cuántos dólares se compraron/retiraron realmente (difieren por el tipo de
-- cambio) y es lo que usa la vista "Mis Ahorros" para el total en esa moneda.
alter table movimientos add column if not exists monto_usd numeric;

-- 17/10/2026 — histórico de Monefy (solo lectura desde la app, vista "Histórico").
-- Tabla APARTE de `movimientos`: no toca Saldo, Resumen ni Ahorros. Se carga una sola vez
-- con un script de consola; sin policy de update a propósito (se borra y recarga).
create table if not exists historial_monefy (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  fecha date not null,
  tipo text not null check (tipo in ('ingreso', 'egreso')),
  categoria_original text not null,
  categoria_hoy text not null,
  descripcion text,
  monto numeric not null,
  created_at timestamptz not null default now()
);
create index if not exists historial_monefy_user_fecha_idx on historial_monefy (user_id, fecha desc);
alter table historial_monefy enable row level security;
drop policy if exists "historial_monefy: select propios" on historial_monefy;
create policy "historial_monefy: select propios" on historial_monefy
  for select using (auth.uid() = user_id);
drop policy if exists "historial_monefy: insert propios" on historial_monefy;
create policy "historial_monefy: insert propios" on historial_monefy
  for insert with check (auth.uid() = user_id);
drop policy if exists "historial_monefy: delete propios" on historial_monefy;
create policy "historial_monefy: delete propios" on historial_monefy
  for delete using (auth.uid() = user_id);

-- 05-06/11/2026 — TARJETAS Y CUOTAS. Tabla de tarjetas (nombre, cierre, vencimiento, límite) y 3 columnas
-- en movimientos. Todo se puede correr más de una vez. Aplicado en TEST y PROD el 08/11/2026.
create table if not exists tarjetas (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nombre text not null,
  cierre date,        -- fecha de cierre del resumen (la carga y ajusta el usuario; la app usa solo el DÍA)
  vencimiento date,   -- fecha de vencimiento del resumen
  orden integer,
  created_at timestamptz not null default now()
);
create index if not exists tarjetas_user_idx on tarjetas (user_id, orden);
alter table tarjetas enable row level security;
drop policy if exists "tarjetas: select propias" on tarjetas;
create policy "tarjetas: select propias" on tarjetas
  for select using (auth.uid() = user_id);
drop policy if exists "tarjetas: insert propias" on tarjetas;
create policy "tarjetas: insert propias" on tarjetas
  for insert with check (auth.uid() = user_id);
drop policy if exists "tarjetas: update propias" on tarjetas;
create policy "tarjetas: update propias" on tarjetas
  for update using (auth.uid() = user_id);
drop policy if exists "tarjetas: delete propias" on tarjetas;
create policy "tarjetas: delete propias" on tarjetas
  for delete using (auth.uid() = user_id);

-- Límite de crédito de la tarjeta (la app muestra límite - cuotas pendientes como "disponible").
alter table tarjetas add column if not exists limite numeric(14,2);

-- Cuotas y tarjeta en movimientos. null = no es compra con tarjeta; 1 = pago completo en el siguiente
-- resumen (o "compra anterior" si lleva cuota_inicio); 2 o más = en cuotas (no suma al Saldo: suma un
-- movimiento mensual "Cuotas <tarjeta>" en M_PAGO que arma la app).
alter table movimientos add column if not exists cuotas integer
  check (cuotas is null or cuotas >= 1);
alter table movimientos add column if not exists tarjeta_id uuid
  references tarjetas(id) on delete set null;
-- Mes de la 1ª cuota (siempre día 1). Se fija al guardar con el cierre de ese momento.
alter table movimientos add column if not exists cuota_inicio date;
