-- Guarda a transcricao do audio. A coluna transcript ja existia em messages,
-- e nunca tinha sido usada.
create or replace function public.nx_wa_set_transcript(p_wamid text, p_texto text)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  update messages set transcript = p_texto, body = coalesce(nullif(body,''), p_texto)
   where wa_message_id = p_wamid;
end $$;

revoke all on function public.nx_wa_set_transcript(text,text) from public, anon, authenticated;
grant execute on function public.nx_wa_set_transcript(text,text) to service_role;

-- Quando a transcricao existe, o audio deixa de precisar do aviso "nao ouco".
create or replace function public.nx_wa_midia_ack(p_conv uuid, p_tipo text)
returns text language plpgsql security definer set search_path to 'public' as $$
declare v_state text; v_active boolean; v_status conv_status; v_suj text; v_artigo text;
begin
  select bot_state, bot_active, status into v_state, v_active, v_status
    from conversations where id = p_conv;
  if v_active is false or v_status in ('aguardando_medico','em_atendimento','agendada','finalizada','resolvida') then
    return null;
  end if;

  v_artigo := case p_tipo
    when 'image' then 'a foto' when 'video' then 'o vídeo'
    when 'audio' then 'o áudio' when 'document' then 'o arquivo'
    else 'o anexo' end;
  v_suj := coalesce(public.nx_wa_pac(p_conv)->>'sujeito','você');

  return case
    when v_state is null then
      '📎 Recebi '||v_artigo||'! Já anexei ao atendimento.'||chr(10)||chr(10)||
      'Me conta em poucas palavras o que está acontecendo?'
    when v_state in ('exame_qual','doc_qual','receita_qual') then
      '📎 Recebi '||v_artigo||'! Já anexei ao atendimento e a equipe vai avaliar.'
    when v_state = 'sintoma' then
      '📎 Recebi '||v_artigo||'! Já anexei.'||chr(10)||chr(10)||
      'Pode me dizer também, em palavras, qual é o principal sintoma de '||v_suj||'?'
    else
      '📎 Recebi '||v_artigo||'! Já anexei ao atendimento.'||chr(10)||chr(10)||
      'Pode continuar respondendo por aqui.'
  end;
end $$;
grant execute on function public.nx_wa_midia_ack(uuid,text) to authenticated, service_role;
