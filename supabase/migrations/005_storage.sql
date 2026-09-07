-- Politica de storage identica a da producao: acesso por pasta = clinic_id,
-- e so quem e membro daquela clinica.
drop policy if exists docs_member_rw on storage.objects;
create policy docs_member_rw on storage.objects as permissive for all to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
  and is_member(((storage.foldername(name))[1])::uuid)
)
with check (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
  and is_member(((storage.foldername(name))[1])::uuid)
);
