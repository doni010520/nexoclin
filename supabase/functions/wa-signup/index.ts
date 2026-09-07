// supabase/functions/wa-signup/index.ts
// Recebe o `code` do Embedded Signup e conecta a clinica sozinha:
// troca por token -> registra o numero no Cloud API -> assina a WABA ->
// aponta o webhook para ca -> grava. O gestor so clicou num botao.
import { createClient } from "npm:@supabase/supabase-js@2";

const URL_SB = Deno.env.get("SUPABASE_URL")!;
const SRV    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON   = Deno.env.get("SUPABASE_ANON_KEY")!;
const VERIFY = Deno.env.get("WA_VERIFY_TOKEN") ?? "";
const GRAPH  = `https://graph.facebook.com/${Deno.env.get("WA_GRAPH_VERSION") ?? "v21.0"}`;
const WEBHOOK = `${URL_SB}/functions/v1/wa-webhook`;

// Enquanto a NexoClin nao tiver Tech Provider proprio, o Embedded Signup roda
// no app do MVF. Trocar estas duas variaveis migra o fluxo, sem tocar no codigo.
const APP_ID     = Deno.env.get("MVF_APP_ID") ?? "";
const APP_SECRET = Deno.env.get("WA_APP_SECRET_MVF") ?? "";

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
  return { ok: r.ok, body: await r.json().catch(() => ({})) };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST")    return json({ erro: "method not allowed" }, 405);

  const jwt = req.headers.get("Authorization") ?? "";
  if (!jwt.startsWith("Bearer ")) return json({ erro: "sem autenticação" }, 401);

  let b: any;
  try { b = await req.json(); } catch { return json({ erro: "json inválido" }, 400); }
  const { clinic_id, code, waba_id, phone_number_id, pin } = b ?? {};
  if (!clinic_id || !code) return json({ erro: "clinic_id e code são obrigatórios" }, 400);

  // 1) So gestor/admin conecta. Checado com o JWT de quem clicou.
  const comoUsuario = createClient(URL_SB, ANON, { global: { headers: { Authorization: jwt } } });
  const { data: pode, error: errPerm } = await comoUsuario.rpc("nx_can_admin", { p_clinic: clinic_id });
  if (errPerm || pode !== true) return json({ erro: "sem permissão", detalhe: errPerm?.message }, 403);

  const passos: Record<string, unknown> = {};

  // 2) Troca o code por token. Este e o unico ponto que usa o app secret.
  const troca = await fetch(
    `${GRAPH}/oauth/access_token?client_id=${APP_ID}&client_secret=${APP_SECRET}&code=${encodeURIComponent(code)}`,
  );
  const tk = await troca.json().catch(() => ({}));
  if (!troca.ok || !tk?.access_token) {
    return json({ erro: "falha ao trocar o código por token", meta: tk?.error ?? tk }, 502);
  }
  const token = tk.access_token as string;
  passos.token = "obtido";

  // 3) Descobre WABA e numero se o popup nao tiver informado.
  let waba = waba_id, phone = phone_number_id;
  if (!waba) {
    const w = await graph("me?fields=businesses{owned_whatsapp_business_accounts{id}}", token);
    waba = w.body?.businesses?.data?.[0]?.owned_whatsapp_business_accounts?.data?.[0]?.id;
  }
  if (waba && !phone) {
    const p = await graph(`${waba}/phone_numbers`, token);
    phone = p.body?.data?.[0]?.id;
  }
  if (!waba || !phone) return json({ erro: "não identifiquei WABA/número", waba, phone, passos }, 409);
  passos.waba_id = waba; passos.phone_number_id = phone;

  // 4) Registra o numero no Cloud API. Sem isto ele nao envia nem recebe.
  //    Ja registrado devolve erro e seguimos: nao e motivo para abortar.
  const reg = await graph(`${phone}/register`, token, {
    method: "POST",
    body: JSON.stringify({ messaging_product: "whatsapp", pin: pin ?? "159357" }),
  });
  passos.register = reg.ok ? "ok" : (reg.body?.error?.message ?? reg.body);

  // 5) Assina a WABA no app. Precisa ser por WABA — nao se herda.
  const sub = await graph(`${waba}/subscribed_apps`, token, { method: "POST" });
  passos.subscribed_apps = sub.ok ? "ok" : (sub.body?.error?.message ?? sub.body);

  // 6) Override do webhook NO NUMERO: isola os eventos desta clinica, mesmo
  //    o app sendo de outro produto.
  const ov = await graph(phone, token, {
    method: "POST",
    body: JSON.stringify({ webhook_configuration: { override_callback_uri: WEBHOOK, verify_token: VERIFY } }),
  });
  passos.override_webhook = ov.ok ? WEBHOOK : (ov.body?.error?.message ?? ov.body);

  // 7) Dados do numero e gravacao.
  const info = await graph(`${phone}?fields=display_phone_number,verified_name,quality_rating`, token);

  const admin = createClient(URL_SB, SRV);
  const { error: errUp } = await admin.from("clinic_whatsapp").upsert({
    clinic_id, provider: "meta_cloud",
    phone_number_id: phone, waba_id: waba, access_token: token,
    display_number: info.body?.display_phone_number ?? null,
    status: ov.ok ? "conectado" : "pendente",
    connected_at: new Date().toISOString(), updated_at: new Date().toISOString(),
  }, { onConflict: "clinic_id" });
  if (errUp) return json({ erro: "falha ao gravar", detalhe: errUp.message, passos }, 500);

  return json({
    ok: true,
    status: ov.ok ? "conectado" : "pendente",
    numero: info.body?.display_phone_number,
    nome_verificado: info.body?.verified_name,
    passos,
  });
});
