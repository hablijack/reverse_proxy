#!/bin/sh

# =============================================================================
# Entrypoint: nginx-Start (einfach + selbstheilend)
#
# - KEIN automatischer Let's-Encrypt-Verkehr beim Start. Ausstellung und
#   Erneuerung werden manuell (oder per Host-Cron) angestoßen.
# - nginx liest das Zertifikat aus /etc/nginx/ssl/. select-cert verlinkt
#   dorthin das Let's-Encrypt-Zertifikat aus dem Volume — oder, falls
#   keines da ist, ein im Container erzeugtes Dummy-Zertifikat. Das
#   Let's-Encrypt-Volume bleibt dabei unangetastet (certbot gehört es
#   allein, dadurch entstehen keine "-0001"-Reihen mehr).
# - Ein certbot-Deploy-Hook verlinkt nach jeder Ausstellung/Erneuerung
#   neu und lädt nginx automatisch neu.
#
# Erstmalige Ausstellung (im laufenden Container):
#
#   docker exec -it reverse-proxy certbot certonly --webroot \
#     -w /var/www/certbot --cert-name garden.dedyn.io -d garden.dedyn.io \
#     --email <deine-adresse> --agree-tos
#
# Erneuerung (erneuert nur, wenn < 30 Tage Restlaufzeit; nginx wird vom
# Hook automatisch neu geladen) — z. B. wöchentlich per Host-Cron:
#
#   docker exec reverse-proxy certbot renew -q
# =============================================================================

set -eu

# Htpasswd für Basic-Auth erzeugen (nur, wenn konfiguriert) — nur für
# root und die nginx-Worker lesbar
if [ -n "${BASIC_AUTH_USER:-}" ]; then
  ( umask 027 && printf '%s\n' "$BASIC_AUTH_USER" | base64 -d > /etc/nginx/htpasswd )
  chown root:nginx /etc/nginx/htpasswd
fi

# certbot-Deploy-Hook ins Volume legen (idempotent, bei jedem Start
# aktualisiert): nach erfolgreicher Ausstellung/Erneuerung Zertifikat
# neu verlinken und nginx neu laden.
HOOK_DIR=/etc/letsencrypt/renewal-hooks/deploy
mkdir -p "$HOOK_DIR"
cat > "$HOOK_DIR/reload-nginx.sh" <<'EOF'
#!/bin/sh
# Verwaltet vom reverse_proxy-Image (wird beim Containerstart überschrieben)
/usr/local/bin/select-cert && nginx -s reload
EOF
chmod 755 "$HOOK_DIR/reload-nginx.sh"

# Zertifikat auswählen und nach /etc/nginx/ssl/ verlinken
/usr/local/bin/select-cert

# ACME-Webroot: Challenge-Verzeichnis sicherstellen (idempotent; deckt
# auch bestehende Volumes ab, die es noch nicht enthalten).
mkdir -p /var/www/certbot/.well-known/acme-challenge

# NGINX IM VORDERGRUND STARTEN (läuft forever)
exec nginx -g 'daemon off;'
