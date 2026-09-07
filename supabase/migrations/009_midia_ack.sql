-- Resposta a arquivo recebido. Sem isto, a mae manda a foto da pele do filho
-- e o atendimento fica mudo — o pior efeito possivel, porque ela nao sabe se
-- chegou e reenvia, ou desiste.
create or replace function public.nx_wa_midia_ack(p_conv uuid, p_tipo text)
returns text language plpgsql security definer set search_path to 'public' as $$
declare v_state text; v_active boolean; v_status conv_status; v_suj text; v_artigo text;
begin
  select bot_state, bot_active, status into v_state, v_active, v_status
    from conversations where id = p_conv;
  -- humano ja assumiu, ou emergencia: o bot nao se mete
  if v_active is false or v_status in ('aguardando_medico','em_atendimento','agendada','finalizada','resolvida') then
    return null;
  end if;

  v_artigo := case p_tipo
    when 'image' then 'a foto'
    when 'video' then 'o vídeo'
    when 'audio' then 'o áudio'
    when 'document' then 'o arquivo'
    else 'o anexo' end;

  v_suj := coalesce(public.nx_wa_pac(p_conv)->>'sujeito','você');

  -- audio precisa de transcricao para virar resposta; por ora, pede texto
  if p_tipo = 'audio' then
    return '📎 Recebi '||v_artigo||'!'||chr(10)||chr(10)||
           'Ainda não consigo ouvir áudios por aqui. Pode escrever em texto, por favor? '||
           'Assim eu registro certinho para o médico.';
  end if;

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

revoke all on function public.nx_wa_midia_ack(uuid,text) from public, anon;
grant execute on function public.nx_wa_midia_ack(uuid,text) to authenticated, service_role;
