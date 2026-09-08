// supabase/functions/wa-connect/index.ts
// Conecta um numero do WhatsApp a uma clinica.
// Serve para os dois caminhos:
//  (a) numero adicionado direto no app da NexoClin;
//  (b) numero vindo do Embedded Signup de OUTRO app (ex.: o Tech Provider do MVF)
//      — nesse caso o override de webhook e o que garante que as mensagens
//      venham para ca em vez de irem para o destino padrao daquele app.
import { createClient } from "npm:@supabase/supabase-js@2";

const URL_SB = Deno.env.get("SUPABASE_URL")!;
const SRV    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON   = Deno.env.get("SUPABASE_ANON_KEY")!;
const VERIFY = Deno.env.get("WA_VERIFY_TOKEN") ?? "";
const GRAPH  = `https://graph.facebook.com/${Deno.env.get("WA_GRAPH_VERSION") ?? "v21.0"}`;
const WEBHOOK = `${URL_SB}/functions/v1/wa-webhook`;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "content-type": "application/json" } });

async function graph(path: string, token: string, init?: RequestInit) {
  const r = await fetch(`${GRAPH}/${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...(init?.headers ?? {}) },
  });
  const body = await r.json().catch(() => ({}));
  return { ok: r.ok, status: r.status, body };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST")    return json({ erro: "method not allowed" }, 405);

  const jwt = req.headers.get("Authorization") ?? "";
  if (!jwt.startsWith("Bearer ")) return json({ erro: "sem autenticação" }, 401);

  let b: any;
  try { b = await req.json(); } catch { return json({ erro: "json inválido" }, 400); }
  const { clinic_id, phone_number_id, waba_id, access_token, display_number } = b ?? {};
  if (!clinic_id || !phone_number_id || !access_token) {
    return json({ erro: "clinic_id, phone_number_id e access_token são obrigatórios" }, 400);
  }

  // 1) So gestor/admin da clinica conecta. Checa COM o JWT de quem chamou.
  const comoUsuario = createClient(URL_SB, ANON, { global: { headers: { Authorization: jwt } } });
  const { data: pode, error: errPerm } = await comoUsuario.rpc("nx_can_admin", { p_clinic: clinic_id });
  if (errPerm || pode !== true) return json({ erro: "sem permissão", detalhe: errPerm?.message }, 403);

  const passos: Record<string, unknown> = {};

  // 2) Confere que o token enxerga o numero e pega os dados reais.
  const info = await graph(
    `${phone_number_id}?fields=display_phone_number,verified_name,quality_rating,code_verification_status,platform_type`,
    access_token,
  );
  if (!info.ok) return json({ erro: "token_invalido_ou_sem_acesso", meta: info.body?.error ?? info.body }, 502);
  passos.numero = info.body;

  // 3) Assina a WABA no app. Precisa ser feito POR WABA — nao e herdado.
  if (waba_id) {
    const sub = await graph(`${waba_id}/subscribed_apps`, access_token, { method: "POST" });
    passos.subscribed_apps = sub.ok ? "ok" : (sub.body?.error ?? sub.body);
  }

  // 4) Override do webhook NO NUMERO. E isto que isola: mesmo num app de
  //    terceiro, os eventos deste numero vem para a NexoClin e nao para o
  //    destino padrao daquele app.
  const ov = await graph(phone_number_id, access_token, {
    method: "POST",
    body: JSON.stringify({
      webhook_configuration: { override_callback_uri: WEBHOOK, verify_token: VERIFY },
    }),
  });
  passos.override_webhook = ov.ok ? WEBHOOK : (ov.body?.error ?? ov.body);

  // 5) Grava a conexao. O token nunca passou pelo navegador do gestor.
  const admin = createClient(URL_SB, SRV);
  const { error: errUp } = await admin.from("clinic_whatsapp").upsert({
    clinic_id,
    provider: "meta_cloud",
    phone_number_id,
    waba_id: waba_id ?? null,
    access_token,
    display_number: display_number ?? info.body?.display_phone_number ?? null,
    status: ov.ok ? "conectado" : "pendente",
    connected_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }, { onConflict: "clinic_id" });
  if (errUp) return json({ erro: "falha ao gravar", detalhe: errUp.message, passos }, 500);

  return json({ ok: true, status: ov.ok ? "conectado" : "pendente", webhook: WEBHOOK, passos });
});
