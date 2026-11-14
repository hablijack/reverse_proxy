#!/bin/sh

# =============================================================================
# Entrypoint: nginx-Start (einfach + selbstheilend)
#
# - KEIN automatischer Let's-Encrypt-Verkehr: keine ACME-Challenge, keine
#   automatische Erneuerung. Das Zertifikat wird MANUELL beantragt.
# - Fehlt das Zertifikat im Volume (Erststart oder leer/beschädigtes
#   Volume), wird ein selbstsigniertes Dummy-Zertifikat mit FRISCH
#   erzeugtem Schlüssel angelegt, damit nginx sauber starten kann (kein
#   Crash-Loop). Es wird bewusst kein Schlüssel im Image/Repo mitgeliefert
#   (der wäre öffentlich bekannt).
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

set -eu

# Htpasswd für Basic-Auth erzeugen (nur, wenn konfiguriert) — nur für
# root und die nginx-Worker lesbar
if [ -n "${BASIC_AUTH_USER:-}" ]; then
  ( umask 027 && printf '%s\n' "$BASIC_AUTH_USER" | base64 -d > /etc/nginx/htpasswd )
  chown root:nginx /etc/nginx/htpasswd
fi

# Zertifikat fehlt (Erststart / leer oder beschädigtes Volume) ->
# Dummy-Zertifikat aus dem Image wiederherstellen, damit nginx starten kann.
if [ ! -s "$LIVE_DIR/fullchain.pem" ] || [ ! -s "$LIVE_DIR/privkey.pem" ]; then
  echo "Kein (vollstaendiges) Zertifikat in $LIVE_DIR —"
  echo "selbstsigniertes Dummy-Zertifikat wird erzeugt (nginx laeuft damit,"
  echo "bis ein echtes Let's-Encrypt-Zertifikat manuell beantragt wird)."
  mkdir -p "$LIVE_DIR"
  rm -f "$LIVE_DIR/fullchain.pem" "$LIVE_DIR/privkey.pem" "$LIVE_DIR/chain.pem"
  ( umask 077 && openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 90 \
      -subj "/CN=$DOMAIN" -addext "subjectAltName=DNS:$DOMAIN" \
      -keyout "$LIVE_DIR/privkey.pem" -out "$LIVE_DIR/fullchain.pem" 2>/dev/null )
  cp "$LIVE_DIR/fullchain.pem" "$LIVE_DIR/chain.pem"
  chmod 644 "$LIVE_DIR/fullchain.pem" "$LIVE_DIR/chain.pem"
fi

# Private Key darf nur root lesen (nginx-Master liest ihn als root)
chmod 600 "$LIVE_DIR/privkey.pem" 2>/dev/null || true

# ACME-Webroot: Challenge-Verzeichnis sicherstellen. certbot legt die
# HTTP-01-Challenge-Dateien unter <webroot>/.well-known/acme-challenge/
# ab — das Verzeichnis muss existieren, damit die Webroot-Issuance
# funktioniert (idempotent; deckt auch bestehende Volumes ab, die es
# noch nicht enthalten).
mkdir -p /var/www/certbot/.well-known/acme-challenge

# NGINX IM VORDERGRUND STARTEN (läuft forever)
exec nginx -g 'daemon off;'
