-- =====================================================================
-- NexoClin | camada pediatrica da triagem
-- O roteiro original assume que quem escreve e o paciente. Numa clinica
-- pediatrica quase nunca e: quem escreve e a mae ou o pai. Isso muda o
-- texto (2a vs 3a pessoa), muda as bandeiras vermelhas e muda o que faz
-- sentido perguntar (escala de 0 a 10 nao serve para bebe).
-- =====================================================================

-- 1) Idade em meses a partir do que a pessoa digitou.
--    "2 meses", "6 anos", "1 ano e 3 meses", "recem nascido", "8".
create or replace function public.nx_idade_meses(p text)
returns integer language plpgsql immutable as $$
declare t text := lower(coalesce(p,'')); anos int; meses int; n int;
begin
  if t ~ '(recem|recém|nasceu|nasceu agora|dias de vida)' then return 0; end if;

  anos  := (regexp_match(t, '(\d+)\s*ano'))[1]::int;
  meses := (regexp_match(t, '(\d+)\s*(mes|mês|meses)'))[1]::int;
  if anos is not null or meses is not null then
    return coalesce(anos,0)*12 + coalesce(meses,0);
  end if;

  -- so um numero: interpreta como anos (o caso comum)
  n := (regexp_match(t, '(\d+)'))[1]::int;
  if n is null then return null; end if;
  return n * 12;
exception when others then return null;
end $$;

-- 2) Quem e o paciente e como falar dele.
create or replace function public.nx_wa_pac(p_conv uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'nome',   c.paciente_nome,
    'meses',  public.nx_idade_meses(c.paciente_idade),
    'terceiro', (c.paciente_nome is not null),
    -- sujeito da frase: "voce" quando fala consigo, o nome quando fala do filho
    'sujeito', case when c.paciente_nome is null then 'você'
                    else split_part(c.paciente_nome,' ',1) end,
    'posse',   case when c.paciente_nome is null then 'seu'
                    else 'de '||split_part(c.paciente_nome,' ',1) end
  ) from conversations c where c.id = p_conv;
$$;

-- 3) Bandeiras vermelhas com idade. As de adulto continuam valendo; abaixo
--    de 12 anos entram as pediatricas, que sao outras palavras e outro peso.
create or replace function public.nx_wa_has_redflag(t text, p_meses integer)
returns boolean language plpgsql immutable set search_path to 'public' as $$
declare
  adulto text[] := array['dor no peito','aperto no peito','falta de ar',
    'nao consigo respirar','não consigo respirar','desmaio','desmaiei','convuls',
    'boca torta','derrame','sangramento','sangrando muito','muito sangue'];
  pedi text[] := array['nao mama','não mama','nao esta mamando','não está mamando',
    'recusa o peito','nao acorda','não acorda','dificil de acordar','difícil de acordar',
    'muito molinho','molinha','prostrad','gemendo','roxo','arroxead','morad',
    'mancha que nao some','mancha que não some','manchas roxas','petequia',
    'nao faz xixi','não faz xixi','sem urinar','fralda seca',
    'puxando o peito','afundando as costelas','respiracao rapida','respiração rápida',
    'nao para de chorar','não para de chorar','choro fraco','nuca dura','vomitando tudo',
    'nao consegue engolir','não consegue engolir','baba muito'];
  p text;
begin
  foreach p in array adulto loop
    if position(p in t) > 0 and not (t ~ ('(sem|não|nao|nem|nenhum)[a-zç-ú ]{0,12}'||p)) then
      return true;
    end if;
  end loop;

  if p_meses is not null and p_meses <= 144 then
    foreach p in array pedi loop
      if position(p in t) > 0 and not (t ~ ('(sem|não|nao|nem|nenhum)[a-zç-ú ]{0,12}'||p)) then
        return true;
      end if;
    end loop;
    -- febre em bebe pequeno e emergencia por si so, mesmo sem outro sinal
    if p_meses < 3 and t ~ '(febre|febril|quente|[0-9]{2}[,.][0-9]|3[89]|4[01])' then
      return true;
    end if;
  end if;
  return false;
end $$;

grant execute on function public.nx_idade_meses(text) to anon, authenticated, service_role;
grant execute on function public.nx_wa_pac(uuid) to authenticated, service_role;
grant execute on function public.nx_wa_has_redflag(text,integer) to authenticated, service_role;
