-- =====================================================================
-- Foto (logo) da clinica. A coluna foto_url ja existia em clinics e nunca
-- tinha sido usada: a tela mostrava as iniciais e o botao dizia "em breve".
-- =====================================================================

-- nx_clinic_get passa a devolver a foto, senao a tela nao tem como exibir.
create or replace function public.nx_clinic_get(p_clinic uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select case when (public.is_member(p_clinic) or public.is_platform_admin())
    then (select to_jsonb(c) from (
      select id,nome,razao_social,nome_fantasia,cnpj,cnes,email,telefone_whatsapp,
             cep,endereco,numero,complemento,bairro,cidade,estado,link_slug,plano,
             responsavel_tecnico,responsavel_crm,foto_url
      from public.clinics where id=p_clinic) c)
    else null end;
$$;

-- Grava o caminho do arquivo no Storage. Só gestor/admin da clínica.
-- Guarda caminho, não URL: o bucket é privado e a tela assina na hora.
create or replace function public.nx_clinic_set_foto(p_clinic uuid, p_path text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_antigo text;
begin
  if not public.nx_can_admin(p_clinic) then raise exception 'sem permissão'; end if;

  select foto_url into v_antigo from clinics where id = p_clinic;
  update clinics set foto_url = nullif(trim(coalesce(p_path,'')),'') where id = p_clinic;

  return jsonb_build_object('ok', true, 'foto_url', nullif(trim(coalesce(p_path,'')),''),
                            'anterior', v_antigo);
end $$;

grant execute on function public.nx_clinic_set_foto(uuid,text) to authenticated, service_role;
