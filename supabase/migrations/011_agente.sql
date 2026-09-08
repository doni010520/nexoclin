-- Contexto que o agente precisa para responder: quem e o paciente, o que ja
-- foi coletado e o historico recente da conversa.
create or replace function public.nx_agent_contexto(p_conv uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v jsonb; v_clinic uuid; v_ativo boolean; v_status conv_status;
begin
  select clinic_id, bot_active, status into v_clinic, v_ativo, v_status
    from conversations where id = p_conv;
  if v_clinic is null then return null; end if;

  -- humano assumiu: o agente cala
  if v_ativo is false or v_status in ('aguardando_medico','em_atendimento','agendada','finalizada','resolvida') then
    return jsonb_build_object('ativo', false);
  end if;

  select jsonb_build_object(
    'ativo', true,
    'clinica', (select nome from clinics where id = v_clinic),
    'paciente_nome', c.paciente_nome,
    'paciente_idade', c.paciente_idade,
    'meses', public.nx_idade_meses(c.paciente_idade),
    'risco', c.risk::text,
    'coletado', coalesce((
      select jsonb_object_agg(d.chave, d.valor)
      from collected_data d where d.conversation_id = p_conv), '{}'::jsonb),
    'historico', coalesce((
      select jsonb_agg(jsonb_build_object('direction', m.direction::text, 'body', m.body)
                       order by m.created_at)
      from (select * from messages where conversation_id = p_conv
            and body is not null and body <> ''
            order by created_at desc limit 24) m), '[]'::jsonb)
  ) into v from conversations c where c.id = p_conv;
  return v;
end $$;

-- Aplica o que o agente decidiu: dados coletados, risco e encaminhamento.
create or replace function public.nx_agent_aplicar(
  p_conv uuid, p_risco text, p_encaminhar boolean, p_dados jsonb
) returns void language plpgsql security definer set search_path to 'public' as $$
declare d jsonb; v_nome text; v_idade text;
begin
  for d in select * from jsonb_array_elements(coalesce(p_dados,'[]'::jsonb)) loop
    if coalesce(d->>'chave','') = '' or coalesce(d->>'valor','') = '' then continue; end if;
    insert into collected_data(conversation_id, chave, valor, atencao, fonte)
      values (p_conv, d->>'chave', d->>'valor', coalesce((d->>'atencao')::boolean,false), 'ia');
    if d->>'chave' = 'paciente_nome'  then v_nome  := d->>'valor'; end if;
    if d->>'chave' = 'paciente_idade' then v_idade := d->>'valor'; end if;
  end loop;

  update conversations set
    paciente_nome  = coalesce(v_nome,  paciente_nome),
    paciente_idade = coalesce(v_idade, paciente_idade),
    risk   = coalesce(nullif(p_risco,'')::risk_level, risk),
    status = case when p_encaminhar then 'aguardando_medico'::conv_status
                  when status = 'nova' then 'em_triagem'::conv_status else status end,
    bot_active = case when p_encaminhar then false else bot_active end,
    attention  = case when p_risco in ('emergencia','muito_urgente') then true else attention end,
    updated_at = now()
  where id = p_conv;
end $$;

revoke all on function public.nx_agent_contexto(uuid) from public, anon, authenticated;
revoke all on function public.nx_agent_aplicar(uuid,text,boolean,jsonb) from public, anon, authenticated;
grant execute on function public.nx_agent_contexto(uuid) to service_role;
grant execute on function public.nx_agent_aplicar(uuid,text,boolean,jsonb) to service_role;
grant execute on function public.nx_wa_has_redflag(text,integer) to service_role;
