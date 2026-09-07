-- =====================================================================
-- NexoClin | nx_wa_ingest e nx_wa_status
-- Funcoes de servico: chamadas SO pela Edge Function (service_role).
-- NAO alteram nx_conv_send nem nada que o front usa hoje.
-- =====================================================================

-- Entrada: mensagem recebida do paciente.
create or replace function public.nx_wa_ingest(
  p_phone_number_id text,
  p_from            text,
  p_nome            text,
  p_type            text,
  p_body            text,
  p_wamid           text,
  p_ts              bigint default null,
  p_payload         jsonb  default null
) returns uuid
language plpgsql security definer set search_path to 'public' as $$
declare
  v_clinic uuid;
  v_conv   uuid;
  v_type   msg_type;
begin
  -- 1) Roteia pelo numero: com app Tech Provider unico, e o phone_number_id
  --    que diz de qual clinica e a mensagem.
  select clinic_id into v_clinic
    from clinic_whatsapp where phone_number_id = p_phone_number_id;
  if v_clinic is null then
    -- Numero desconhecido: nao perde o evento, guarda para investigar.
    insert into webhook_events(event_type, origem, payload)
      values ('whatsapp_sem_clinica','meta_cloud',
              jsonb_build_object('phone_number_id',p_phone_number_id,'msg',p_payload));
    return null;
  end if;

  -- 2) Tipo desconhecido nao pode derrubar a ingestao.
  begin v_type := p_type::msg_type; exception when others then v_type := 'unsupported'; end;

  -- 3) Conversa: reabre a existente do mesmo telefone ou cria nova.
  select id into v_conv
    from conversations
   where clinic_id = v_clinic
     and nx_fone_key(telefone) = nx_fone_key(p_from)
     and status not in ('finalizada','resolvida')
   order by created_at desc limit 1;

  if v_conv is null then
    insert into conversations(clinic_id, telefone, responsavel_nome, canal, status, stage)
      values (v_clinic, p_from, nullif(p_nome,''), 'WhatsApp', 'nova', 'Aguardando atendente')
      returning id into v_conv;
  else
    update conversations
       set responsavel_nome = coalesce(responsavel_nome, nullif(p_nome,'')),
           updated_at = now()
     where id = v_conv;
  end if;

  -- 4) Mensagem. ON CONFLICT torna a reentrega da Meta inofensiva.
  insert into messages(conversation_id, direction, type, body, author, wa_message_id, created_at)
    values (v_conv, 'in', v_type, p_body, coalesce(nullif(p_nome,''),'paciente'), p_wamid,
            coalesce(to_timestamp(nullif(p_ts,0)), now()))
    on conflict (wa_message_id) where wa_message_id is not null do nothing;

  return v_conv;
end $$;

-- Saida: atualizacao de entrega (sent/delivered/read/failed).
create or replace function public.nx_wa_status(
  p_phone_number_id text,
  p_wamid           text,
  p_status          text,
  p_ts              bigint default null,
  p_erro            jsonb  default null
) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  update messages
     set wa_status    = p_status,
         wa_status_at = coalesce(to_timestamp(nullif(p_ts,0)), now()),
         wa_error     = coalesce(p_erro, wa_error)
   where wa_message_id = p_wamid;
end $$;

-- Estas funcoes sao de servico: so a Edge Function (service_role) chama.
revoke all on function public.nx_wa_ingest(text,text,text,text,text,text,bigint,jsonb) from public, anon, authenticated;
revoke all on function public.nx_wa_status(text,text,text,bigint,jsonb) from public, anon, authenticated;
grant execute on function public.nx_wa_ingest(text,text,text,text,text,text,bigint,jsonb) to service_role;
grant execute on function public.nx_wa_status(text,text,text,bigint,jsonb) to service_role;
