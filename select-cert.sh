#!/bin/sh
# =============================================================================
# select-cert: verlinkt das zu verwendende Zertifikat nach /etc/nginx/ssl/
#
# nginx liest IMMER /etc/nginx/ssl/fullchain.pem + privkey.pem. Dieses
# Skript entscheidet, worauf die Links zeigen:
#
#   1. Let's-Encrypt-Zertifikat aus /etc/letsencrypt/live/<DOMAIN> oder
#      einer certbot-Reihe <DOMAIN>-NNNN (höchste Nummer zuerst) — das
#      erste gültige (nicht abgelaufen, Key passt zum Zertifikat) gewinnt.
#   2. Sonst ein abgelaufenes, aber konsistentes LE-Zertifikat.
#   3. Sonst ein selbstsigniertes Dummy-Zertifikat, das NUR im Container
#      liegt (nicht im Let's-Encrypt-Volume -> keine Konflikte mit certbot).
#
# Wird vom Entrypoint beim Start und von certbot als Deploy-Hook nach
# jeder Ausstellung/Erneuerung aufgerufen.
# =============================================================================
set -eu

DOMAIN="${DOMAIN:-garden.dedyn.io}"
LE_LIVE="/etc/letsencrypt/live"
SSL_DIR="/etc/nginx/ssl"
DUMMY_DIR="$SSL_DIR/dummy"

# Passt der Private Key zum Zertifikat? (RSA + ECDSA)
key_matches() {
  c=$(openssl x509 -in "$1/fullchain.pem" -noout -pubkey 2>/dev/null | sha256sum) || return 1
  k=$(openssl pkey -in "$1/privkey.pem" -pubout 2>/dev/null | sha256sum) || return 1
  [ -n "$c" ] && [ "$c" = "$k" ]
}

usable() {
  [ -s "$1/fullchain.pem" ] && [ -s "$1/privkey.pem" ] && key_matches "$1"
}

not_expired() {
  openssl x509 -in "$1/fullchain.pem" -noout -checkend 0 >/dev/null 2>&1
}

# Kandidaten: exakter Name zuerst, dann certbot-Reihen absteigend
candidates() {
  [ -e "$LE_LIVE/$DOMAIN" ] && echo "$LE_LIVE/$DOMAIN"
  ls -d "$LE_LIVE/$DOMAIN"-[0-9][0-9][0-9][0-9] 2>/dev/null | sort -r || true
}

selected=""
fallback=""
for d in $(candidates); do
  if ! usable "$d"; then
    echo "select-cert: WARNUNG — $d unvollstaendig oder Key passt nicht zum Zertifikat, uebersprungen."
    continue
  fi
  if not_expired "$d"; then selected="$d"; break; fi
  [ -z "$fallback" ] && fallback="$d"
done
[ -z "$selected" ] && selected="$fallback"

mkdir -p "$SSL_DIR"
chmod 700 "$SSL_DIR"

if [ -z "$selected" ]; then
  if ! usable "$DUMMY_DIR"; then
    echo "select-cert: kein Let's-Encrypt-Zertifikat fuer $DOMAIN gefunden —"
    echo "select-cert: erzeuge selbstsigniertes Dummy-Zertifikat."
    mkdir -p "$DUMMY_DIR"
    ( umask 077 && openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -sha256 -days 90 -subj "/CN=$DOMAIN" -addext "subjectAltName=DNS:$DOMAIN" \
        -keyout "$DUMMY_DIR/privkey.pem" -out "$DUMMY_DIR/fullchain.pem" 2>/dev/null )
  fi
  selected="$DUMMY_DIR"
  echo "select-cert: verwende DUMMY-Zertifikat (Browser zeigen eine Warnung)."
elif ! not_expired "$selected"; then
  echo "select-cert: WARNUNG — $selected ist ABGELAUFEN, bitte erneuern."
else
  echo "select-cert: verwende $selected ($(openssl x509 -in "$selected/fullchain.pem" -noout -enddate))"
fi

ln -sfn "$selected/fullchain.pem" "$SSL_DIR/fullchain.pem"
ln -sfn "$selected/privkey.pem"   "$SSL_DIR/privkey.pem"
