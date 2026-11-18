-- JÁ APLICADA em 17/11/2026 (registrada aqui depois, para histórico).
-- Itens 1–3: teste de 24h começa na 1ª questão respondida; métrica de ativação no admin.

create table if not exists public.teste_gratis(
  user_id uuid primary key references auth.users(id) on delete cascade,
  iniciado_em timestamptz not null default now()
);
alter table public.teste_gratis enable row level security;
drop policy if exists teste_gratis_ler_proprio on public.teste_gratis;
create policy teste_gratis_ler_proprio on public.teste_gratis for select using (auth.uid() = user_id);

create or replace function public._iniciar_teste_gratis() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.teste_gratis(user_id, iniciado_em)
  values (new.user_id, least(now(), coalesce(new.criado_em, now())))
  on conflict (user_id) do nothing;
  return new;
end $$;
revoke all on function public._iniciar_teste_gratis() from public, anon, authenticated;

drop trigger if exists trg_iniciar_teste_gratis on public.respostas;
create trigger trg_iniciar_teste_gratis after insert on public.respostas
  for each row execute function public._iniciar_teste_gratis();

insert into public.teste_gratis(user_id, iniciado_em)
select u.id, u.created_at from auth.users u
where exists (select 1 from public.respostas r where r.user_id = u.id)
on conflict (user_id) do nothing;

-- Também foram reescritas (troca de "24h desde o cadastro" por "24h desde teste_gratis.iniciado_em"):
--   public.tem_acesso(), public.admin_alunos(), public.admin_metricas() (+ chave 'ativacao_semanas').
