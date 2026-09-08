-- =====================================================================
-- NexoClin | entrada do WhatsApp (Meta Cloud API)
-- Migration ADITIVA: nao altera nenhuma funcao existente, nao muda
-- comportamento do front que ja esta no ar. Seguro rodar com a producao
-- do dono apontando para este mesmo banco.
-- =====================================================================

-- 1) Tipos de mensagem que a Meta entrega e o enum ainda nao aceita.
--    Sem isso, figurinha/localizacao/botao estouram o insert.
alter type msg_type add value if not exists 'sticker';
alter type msg_type add value if not exists 'location';
alter type msg_type add value if not exists 'contact';
alter type msg_type add value if not exists 'interactive';
alter type msg_type add value if not exists 'button';
alter type msg_type add value if not exists 'unsupported';
