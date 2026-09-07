-- Grava o caminho da midia baixada da Meta. O front ja sabe assinar esse
-- caminho no bucket 'documentos' (rcSignMedia -> createSignedUrl).
create or replace function public.nx_wa_media_set(p_wamid text, p_path text)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  update messages set media_url = p_path where wa_message_id = p_wamid;
end $$;

revoke all on function public.nx_wa_media_set(text,text) from public, anon, authenticated;
grant execute on function public.nx_wa_media_set(text,text) to service_role;

-- Guarda o id da midia na Meta enquanto o download nao acontece, para dar
-- para reprocessar depois se o download falhar.
alter table public.messages add column if not exists wa_media_id text;

create or replace function public.nx_wa_media_pendentes()
returns table(wa_message_id text, wa_media_id text, conversation_id uuid)
language sql security definer set search_path to 'public' as $$
  select m.wa_message_id, m.wa_media_id, m.conversation_id
  from messages m
  where m.wa_media_id is not null and m.media_url is null
  order by m.created_at desc limit 200;
$$;
revoke all on function public.nx_wa_media_pendentes() from public, anon, authenticated;
grant execute on function public.nx_wa_media_pendentes() to service_role;
