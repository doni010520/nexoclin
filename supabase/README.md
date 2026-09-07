# WhatsApp oficial — o que precisa estar configurado

Esta pasta traz a integração com a WhatsApp Business Cloud API: recebimento,
envio, mídia, conexão do número pela clínica e o agente de triagem.

## Onde ficam os segredos

**Nada disso vai em variável de ambiente da Vercel.** O site é HTML estático,
sem build — a Vercel só entrega arquivo, e nada no navegador pode guardar
segredo. O que está no `nexoclin.html` é apenas a `anon key`, que é pública por
design e protegida por RLS.

Os segredos ficam nos **secrets das Edge Functions do Supabase**
(*Project Settings → Edge Functions → Secrets*), porque é lá que roda o código
que fala com a Meta e com a OpenAI.

| Secret | Para que serve | Onde obter |
|---|---|---|
| `WA_APP_SECRET` | valida a assinatura `X-Hub-Signature-256` do webhook | Meta → app da NexoClin → Configurações → Básico |
| `WA_APP_SECRET_MVF` | idem, para clínicas conectadas pelo app parceiro | Meta → app parceiro → Configurações → Básico |
| `WA_VERIFY_TOKEN` | handshake de verificação do webhook | você inventa; o mesmo valor vai na Meta |
| `MVF_APP_ID` | troca do `code` por token no Embedded Signup | ID do app parceiro |
| `WA_SIGNUP_CONFIG_ID` | qual configuração de cadastro incorporado usar | Meta → Login do Facebook para empresas → Configurações |
| `OPENAI_API_KEY` | agente de triagem e transcrição de áudio | platform.openai.com |
| `WA_AGENT_MODEL` | modelo da conversa (padrão `gpt-4.1`) | opcional |
| `WA_STT_MODEL` | modelo de transcrição (padrão `gpt-4o-transcribe`) | opcional |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` o Supabase
injeta sozinho — não configure.

O **token do WhatsApp de cada clínica não é secret**: ele varia por clínica e
fica em `clinic_whatsapp`, protegido por RLS. Só a Edge Function lê, com service
role. Nunca chega ao navegador.

## Ordem de instalação

1. **Migrations** (`supabase/migrations/`), na ordem numérica. São aditivas:
   criam colunas, índices e funções novas, e não alteram nada que já existia.
   A única irreversível é a `001`, que adiciona valores ao enum `msg_type`
   (Postgres não remove valor de enum).
2. **Bucket** `documentos` precisa existir (a `005` cria a política de acesso).
3. **Edge Functions** (`supabase/functions/`), todas com **verificação de JWT
   desligada** no caso do `wa-webhook` — a Meta não manda token do Supabase, e
   com JWT ligado toda chamada dela volta 401.
4. **Secrets** da tabela acima.
5. Na Meta, apontar o webhook para
   `https://<projeto>.supabase.co/functions/v1/wa-webhook` e assinar `messages`.

## As funções

| Função | O que faz |
|---|---|
| `wa-webhook` | recebe mensagens e status da Meta. Valida assinatura, grava o payload cru em `webhook_events`, insere na fila, baixa mídia e transcreve áudio. Responde 200 sempre — erro nosso com 500 faz a Meta reentregar e, depois de falhar muito, desinscrever o app. |
| `wa-send` | envio do cockpit. Confere permissão pelo JWT do atendente, resolve o token da clínica com service role, respeita a janela de 24h e grava o `wamid` devolvido. |
| `wa-signup` | recebe o `code` do Embedded Signup, troca por token, registra o número, assina a WABA e aponta o webhook para este projeto. |
| `wa-connect` | mesma coisa, para número que já existe (conexão manual). |
| `wa-agent` | agente de triagem. Roda um piso determinístico de bandeiras vermelhas **antes** do modelo; se disparar, o modelo nem é consultado. O agente só pode subir a gravidade, nunca baixar. |

## Uma nota sobre o agente

O `wa-agent` conduz a conversa, mas a segurança não depende dele. As frases de
emergência são checadas por `nx_wa_has_redflag`, que roda em SQL, é auditável e
custa zero. O modelo entra para entender o que a lista de palavras não pega
("tá roxinho os labinho dele"). Se os dois discordarem, vale o mais grave.
