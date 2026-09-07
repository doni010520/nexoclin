-- =====================================================================
-- NexoClin | apoio ao envio (saida)
-- A Edge Function wa-send faz a chamada HTTP; o banco so autoriza e grava.
-- NAO altera nx_conv_send: o front atual continua funcionando como hoje.
-- =====================================================================

-- 1) Autorizacao + contexto do envio. Chamada COM o JWT do atendente.
--    De proposito NAO devolve o token da clinica: quem busca o token e a
--    Edge Function, com service_role, para o segredo nunca chegar ao browser.
create or replace function public.nx_wa_can_send(p_conv uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare cl uuid; tel text; ult timestamptz; pnid text;
begin
  cl := nx_conv_clinic(p_conv);
  if cl is null or not (is_member(cl) or is_platform_admin()) then
    raise exception 'sem permissão';
  end if;

  select telefone into tel from conversations where id = p_conv;
  select phone_number_id into pnid from clinic_whatsapp where clinic_id = cl;

  -- janela de 24h: contada a partir da ULTIMA mensagem recebida do paciente
  select max(created_at) into ult
    from messages where conversation_id = p_conv and direction = 'in';

  return jsonb_build_object(
    'clinic_id', cl,
    'telefone', tel,
    'phone_number_id', pnid,
    'ultima_entrada', ult,
    'janela_aberta', (ult is not null and ult > now() - interval '24 hours')
  );
end $$;

-- 2) Grava a mensagem enviada, ja com o wamid devolvido pela Meta.
--    Servico: so a Edge Function (service_role) chama.
create or replace function public.nx_wa_record_out(
  p_conv uuid, p_body text, p_wamid text, p_type text default 'text', p_author text default 'equipe'
) returns uuid language plpgsql security definer set search_path to 'public' as $$
declare v_type msg_type; v_id uuid;
begin
  begin v_type := p_type::msg_type; exception when others then v_type := 'text'; end;
  insert into messages(conversation_id, direction, type, body, author, wa_message_id, wa_status)
    values (p_conv, 'out', v_type, p_body, p_author, p_wamid, 'sent')
    on conflict (wa_message_id) where wa_message_id is not null do nothing
    returning id into v_id;
  update conversations set updated_at = now() where id = p_conv;
  return v_id;
end $$;

revoke all on function public.nx_wa_record_out(uuid,text,text,text,text) from public, anon, authenticated;
grant execute on function public.nx_wa_record_out(uuid,text,text,text,text) to service_role;
grant execute on function public.nx_wa_can_send(uuid) to authenticated, service_role;
