# Ambiente de desenvolvimento do NexoClin na VPS.
# Site estatico: traduz os rewrites do vercel.json para o nginx.
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html conectar.html nexoclin.html docs-api.html docs-auditoria.html favicon.png /usr/share/nginx/html/
EXPOSE 80
