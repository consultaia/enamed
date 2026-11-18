-- ============================================================================
-- Item 8 — Quem já pagou nunca perde quando a faculdade contrata (APLICADA em 18/11/2026)
--
-- Ao entrar numa turma institucional, se o aluno tem assinatura individual paga com dias sobrando:
--   1. os dias que sobram são guardados (tabela dias_guardados);
--   2. a assinatura paga é encerrada agora (expira_em = now(); nenhuma linha é apagada);
--   3. o aluno recebe o acesso institucional até o fim da turma.
-- Quando o acesso da faculdade termina (ou a turma é desativada), os dias guardados voltam,
-- somados a partir do fim de qualquer outro acesso que ele ainda tenha. A devolução acontece
-- na próxima vez que o aluno abre o app (função devolver_dias_guardados, chamada no carregamento).
-- Acesso sem prazo (expira_em nulo) não é mexido.
-- ============================================================================

create table if not exists public.dias_guardados(
  id               bigserial primary key,
  user_id          uuid not null references auth.users(id) on delete cascade,
  turma_id         uuid references public.turmas(id) on delete set null,
  plano            text not null,              -- plano pago que estava ativo (volta com o mesmo plano)
  dias             numeric not null,           -- dias que sobravam no momento de entrar na turma
  expira_original  timestamptz not null,
  guardado_em      timestamptz not null default now(),
  devolvido_em     timestamptz
);
create index if not exists dias_guardados_pendentes_idx on public.dias_guardados(user_id) where devolvido_em is null;
alter table public.dias_guardados enable row level security;
create policy dias_guardados_ler_proprio on public.dias_guardados for select using (auth.uid() = user_id);
-- ninguém escreve direto: só pelas funções abaixo

-- Matrícula na turma (substitui a versão atual)
create or replace function public._matricular(p_turma uuid, p_uid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t record; v_pago record;
begin
  select * into t from turmas where id = p_turma;
  if t.id is null or t.acesso_ate <= now() then return; end if;
  insert into turma_alunos(turma_id, user_id) values (t.id, p_uid) on conflict do nothing;

  -- acesso sem prazo: nada a fazer
  if exists (select 1 from assinaturas where user_id = p_uid and status = 'ativa' and plano <> 'free' and expira_em is null) then
    return;
  end if;

  -- guarda os dias pagos que sobram e encerra a assinatura individual agora
  select plano, expira_em into v_pago from assinaturas
   where user_id = p_uid and status = 'ativa' and plano not in ('free','cortesia','institucional') and expira_em > now()
   order by expira_em desc limit 1;
  if v_pago.expira_em is not null then
    insert into dias_guardados(user_id, turma_id, plano, dias, expira_original)
    values (p_uid, t.id, v_pago.plano, extract(epoch from (v_pago.expira_em - now())) / 86400.0, v_pago.expira_em);
    update assinaturas set expira_em = now()
     where user_id = p_uid and status = 'ativa' and plano not in ('free','cortesia','institucional') and expira_em > now();
  end if;

  -- acesso institucional (não encurta uma cortesia ou institucional mais longa que já exista)
  if not exists (select 1 from assinaturas where user_id = p_uid and status = 'ativa'
                 and plano in ('cortesia','institucional') and expira_em >= t.acesso_ate) then
    insert into assinaturas(user_id, plano, status, expira_em, gateway, referencia)
    values (p_uid, 'institucional', 'ativa', t.acesso_ate, 'instituicao', t.id::text);
  end if;
end $$;

-- Devolução dos dias guardados quando nenhuma turma do aluno está mais ativa
create or replace function public._devolver_dias(p_uid uuid) returns json
language plpgsql security definer set search_path = public as $$
declare g record; v_base timestamptz; v_n int := 0; v_dias numeric := 0;
begin
  if exists (select 1 from turma_alunos ta join turmas t on t.id = ta.turma_id
             where ta.user_id = p_uid and t.ativo and t.acesso_ate > now()) then
    return json_build_object('devolvidos', 0, 'dias', 0);
  end if;
  for g in select * from dias_guardados where user_id = p_uid and devolvido_em is null order by guardado_em for update loop
    select greatest(now(), coalesce(max(expira_em), now())) into v_base
      from assinaturas where user_id = p_uid and status = 'ativa' and plano not in ('free','institucional') and expira_em is not null;
    insert into assinaturas(user_id, plano, status, expira_em, gateway, referencia)
    values (p_uid, g.plano, 'ativa', v_base + make_interval(secs => g.dias * 86400), 'devolucao', 'dias_guardados_' || g.id);
    update dias_guardados set devolvido_em = now() where id = g.id;
    v_n := v_n + 1; v_dias := v_dias + g.dias;
  end loop;
  return json_build_object('devolvidos', v_n, 'dias', round(v_dias));
end $$;
revoke all on function public._devolver_dias(uuid) from public, anon, authenticated;

create or replace function public.devolver_dias_guardados() returns json
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return json_build_object('devolvidos', 0, 'dias', 0); end if;
  return public._devolver_dias(auth.uid());
end $$;

-- Métrica do admin: a devolução não é um pagamento novo
do $$
declare d text; n text;
begin
  d := pg_get_functiondef('public.admin_metricas'::regproc);
  n := replace(d, '''pagos_30d'',        (select count(*) from assinaturas where status=''ativa'' and plano not in (''free'',''cortesia'') and criado_em > now() - interval ''30 days'')',
                  '''pagos_30d'',        (select count(*) from assinaturas where status=''ativa'' and plano not in (''free'',''cortesia'') and coalesce(gateway,'''') <> ''devolucao'' and criado_em > now() - interval ''30 days'')');
  if n = d then raise exception 'admin_metricas pagos_30d: trecho não encontrado'; end if;
  execute n;
end $$;
