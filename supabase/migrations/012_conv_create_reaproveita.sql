-- Criar atendimento reaproveita a conversa aberta do mesmo telefone em vez
-- de abrir duplicata na fila.
create or replace function public.nx_conv_create(
  p_clinic uuid, p_nome text, p_telefone text, p_mensagem text
) returns uuid language plpgsql security definer set search_path to 'public' as $$
declare v_conv uuid;
begin
  if not (is_member(p_clinic) or is_platform_admin()) then
    raise exception 'sem permissão';
  end if;

  select id into v_conv from conversations
   where clinic_id = p_clinic
     and nx_fone_key(telefone) = nx_fone_key(p_telefone)
     and status not in ('finalizada','resolvida')
   order by created_at desc limit 1;

  if v_conv is null then
    insert into conversations(clinic_id, telefone, responsavel_nome, canal, status, stage)
      values (p_clinic, p_telefone, nullif(p_nome,''), 'WhatsApp', 'nova', 'Aguardando atendente')
      returning id into v_conv;
  else
    update conversations
       set responsavel_nome = coalesce(responsavel_nome, nullif(p_nome,'')), updated_at = now()
     where id = v_conv;
  end if;

  if coalesce(p_mensagem,'') <> '' then
    insert into messages(conversation_id, direction, type, body, author)
      values (v_conv, 'in', 'text', p_mensagem, coalesce(nullif(p_nome,''),'paciente'));
  end if;

  return v_conv;
end $$;

grant execute on function public.nx_conv_create(uuid,text,text,text) to authenticated, service_role;
