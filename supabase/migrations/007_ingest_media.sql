-- nx_wa_ingest passa a guardar o id da midia da Meta.
-- Continua ADITIVO: mesma assinatura + um parametro opcional no fim.
create or replace function public.nx_wa_ingest(
  p_phone_number_id text,
  p_from            text,
  p_nome            text,
  p_type            text,
  p_body            text,
  p_wamid           text,
  p_ts              bigint default null,
  p_payload         jsonb  default null,
  p_media_id        text   default null
) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_clinic uuid; v_conv uuid; v_type msg_type;
begin
  select clinic_id into v_clinic
    from clinic_whatsapp where phone_number_id = p_phone_number_id;
  if v_clinic is null then
    insert into webhook_events(event_type, origem, payload)
      values ('whatsapp_sem_clinica','meta_cloud',
              jsonb_build_object('phone_number_id',p_phone_number_id,'msg',p_payload));
    return null;
  end if;

  begin v_type := p_type::msg_type; exception when others then v_type := 'unsupported'; end;

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
       set responsavel_nome = coalesce(responsavel_nome, nullif(p_nome,'')), updated_at = now()
     where id = v_conv;
  end if;

  insert into messages(conversation_id, direction, type, body, author, wa_message_id, wa_media_id, created_at)
    values (v_conv, 'in', v_type, p_body, coalesce(nullif(p_nome,''),'paciente'), p_wamid, p_media_id,
            coalesce(to_timestamp(nullif(p_ts,0)), now()))
    on conflict (wa_message_id) where wa_message_id is not null do nothing;

  -- devolve o contexto que a Edge Function precisa para baixar a midia
  return jsonb_build_object('conversation_id', v_conv, 'clinic_id', v_clinic);
end $$;

revoke all on function public.nx_wa_ingest(text,text,text,text,text,text,bigint,jsonb,text) from public, anon, authenticated;
grant execute on function public.nx_wa_ingest(text,text,text,text,text,text,bigint,jsonb,text) to service_role;
-- remove a versao antiga (retornava uuid) para nao ficar ambiguidade
drop function if exists public.nx_wa_ingest(text,text,text,text,text,text,bigint,jsonb);
