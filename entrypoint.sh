#!/bin/sh

# =============================================================================
# Entrypoint: nginx-Start (einfach + selbstheilend)
#
# - KEIN automatischer Let's-Encrypt-Verkehr: keine ACME-Challenge, keine
#   automatische Erneuerung. Das Zertifikat wird MANUELL beantragt.
# - Fehlt das Zertifikat im Volume (Erststart oder leer/beschädigtes
#   Volume), wird das Dummy-Zertifikat aus dem Image wiederhergestellt,
#   damit nginx sauber starten kann (kein Crash-Loop).
#
# Manuelle Zertifikats-Issuance (nach dem Start, sobald die
# Let's-Encrypt-Rate-Limits für die Domain abgelaufen sind):
#
#   docker exec -it reverse-proxy sh
#   certbot certonly --webroot -w /var/www/certbot \
#     --email christoph.habel@posteo.de -d garden.dedyn.io \
#     --rsa-key-size 4096 --agree-tos --force-renewal
#   nginx -s reload
#
#   (certonly registriert bei Bedarf automatisch das LE-Konto und legt
#   ein Renewal-Config an; spätere Erneuerungen laufen dann über
#   'certbot renew'.)
# =============================================================================

DOMAIN="garden.dedyn.io"
LIVE_DIR="/etc/letsencrypt/live/$DOMAIN"
DUMMY_DIR="/opt/dummy-certs"

# Htpasswd für Basic-Auth erzeugen (nur, wenn konfiguriert)
if [ -n "$BASIC_AUTH_USER" ]; then
  echo "$BASIC_AUTH_USER" | base64 -d > /etc/nginx/htpasswd
fi

# Zertifikat fehlt (Erststart / leer oder beschädigtes Volume) ->
# Dummy-Zertifikat aus dem Image wiederherstellen, damit nginx starten kann.
if [ ! -f "$LIVE_DIR/fullchain.pem" ] || [ ! -f "$LIVE_DIR/privkey.pem" ]; then
  echo "Kein (vollstaendiges) Zertifikat in $LIVE_DIR —"
  echo "Dummy-Zertifikat wird wiederhergestellt (nginx laeuft damit, bis ein"
  echo "echtes Let's-Encrypt-Zertifikat manuell beantragt wird)."
  mkdir -p "$LIVE_DIR"
  cp -a "$DUMMY_DIR/." "$LIVE_DIR/"
fi

# ACME-Webroot: Challenge-Verzeichnis sicherstellen. certbot legt die
# HTTP-01-Challenge-Dateien unter <webroot>/.well-known/acme-challenge/
# ab — das Verzeichnis muss existieren, damit die Webroot-Issuance
# funktioniert (idempotent; deckt auch bestehende Volumes ab, die es
# noch nicht enthalten).
mkdir -p /var/www/certbot/.well-known/acme-challenge

# NGINX IM VORDERGRUND STARTEN (läuft forever)
exec nginx -g 'daemon off;'
