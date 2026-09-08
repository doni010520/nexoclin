-- =====================================================================
-- NexoClin | entrada do WhatsApp - parte 2
-- (separada porque valor novo de enum so pode ser usado em outra transacao)
-- =====================================================================

-- 2) Chave de telefone tolerante ao formato brasileiro.
--    A Meta manda "5581987593444"; o banco tem "81987593444"; e para
--    numeros antigos o wa_id vem SEM o nono digito. Casar por igualdade
--    de string cria conversa nova a cada mensagem.
--    Estrategia: pais + DDD + ULTIMOS 8 digitos (o nono some dos dois lados).
create or replace function public.nx_fone_key(p text)
returns text language sql immutable as $$
  with d as (select regexp_replace(coalesce(p,''), '\D', '', 'g') as n)
  select case
    when length(n) = 0 then null
    -- BR com DDI: 55 + DDD(2) + 8 ou 9 digitos
    when length(n) between 12 and 13 and left(n,2) = '55'
      then '55' || substr(n,3,2) || right(n,8)
    -- BR sem DDI: DDD(2) + 8 ou 9 digitos
    when length(n) between 10 and 11
      then '55' || left(n,2) || right(n,8)
    else n
  end from d;
$$;

-- 3) Colunas que faltam em messages para o WhatsApp funcionar.
alter table public.messages add column if not exists wa_message_id text;
alter table public.messages add column if not exists wa_status     text;
alter table public.messages add column if not exists wa_status_at  timestamptz;
alter table public.messages add column if not exists wa_error      jsonb;

-- Idempotencia: a Meta REENTREGA o mesmo evento. Sem isto, a fila duplica.
create unique index if not exists messages_wa_message_id_key
  on public.messages (wa_message_id) where wa_message_id is not null;

-- 4) Chave de upsert da conversa. Sem isto, duas mensagens do mesmo
--    paciente chegando juntas criam duas conversas.
-- Busca da conversa aberta pelo telefone normalizado. NAO e unico de
-- proposito: a base de demonstracao reusa o mesmo telefone para pacientes
-- diferentes, e um indice unico recusaria esses registros. A garantia de nao
-- duplicar a fila fica em nx_wa_ingest, que procura antes de inserir.
create index if not exists conversations_clinic_fone_idx
  on public.conversations (clinic_id, public.nx_fone_key(telefone))
  where clinic_id is not null and telefone is not null;

-- 5) Busca da clinica pelo numero: e o roteamento do webhook (app unico).
create index if not exists clinic_whatsapp_phone_number_id_idx
  on public.clinic_whatsapp (phone_number_id);

-- 6) Rastreio de reprocessamento do que ja caiu em webhook_events.
alter table public.webhook_events add column if not exists processed_at timestamptz;
