#!/bin/sh

# =============================================================================
# Entrypoint: Let's-Encrypt-Verwaltung + nginx-Start
#
# - Zertifikate existieren (/etc/letsencrypt/archive):
#   nginx laeuft kurz im Hintergrund, damit certbot bei Bedarf ueber den
#   Webroot (Port 80) erneuern KANN (solange das Zertifikat gueltig ist,
#   ist 'certbot renew' ein No-Op ohne ACME-Verkehr). Danach laeuft
#   nginx im Vordergrund.
#
# - Noch kein Zertifikat (Erststart):
#   nginx laeuft im Hintergrund und bedient die ACME-HTTP-01-Challenge.
#   Das Dummy-Zertifikat wird NICHT geloescht, sondern nur ersetzt, wenn
#   die Issuance erfolgreich war. Schlaegt sie fehl, startet nginx trotzdem
#   (mit dem Dummy-Zertifikat) — der Container crasht nicht im Loop, und
#   der naechste Start versucht es erneut (max. 1x/Stunde, um die
#   Let's-Encrypt-Rate-Limits zu respektieren).
# =============================================================================

ARCHIVE="/etc/letsencrypt/archive"
DOMAIN="garden.dedyn.io"
WEBROOT="/var/www/certbot"
EMAIL="christoph.habel@posteo.de"
ATTEMPT_FILE="$WEBROOT/.last-issuance-attempt"

# CREATE HTPASS FOR BASIC-AUTH-ACCESS (nur, wenn konfiguriert)
if [ -n "$BASIC_AUTH_USER" ]; then
  echo "$BASIC_AUTH_USER" | base64 -d > /etc/nginx/htpasswd
fi

start_bg_nginx() {
  /usr/sbin/nginx
  BG_PID=$(pidof nginx)
  if [ -z "$BG_PID" ]; then
    echo "WARNING: Hintergrund-nginx ist nicht gestartet (Port belegt? Zertifikat fehlt?)"
  fi
}

stop_bg_nginx() {
  if [ -n "$BG_PID" ]; then
    kill "$BG_PID" 2>/dev/null
    i=0
    while [ "$i" -lt 25 ] && kill -0 "$BG_PID" 2>/dev/null; do
      sleep 0.2
      i=$((i + 1))
    done
    kill -9 "$BG_PID" 2>/dev/null
  fi
  BG_PID=""
}

if [ -d "$ARCHIVE" ]; then
  # ---- Zertifikate existieren: bei Bedarf erneuern -------------------------
  if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo "ERROR: /etc/letsencrypt/archive existiert, aber das Live-Zertifikat"
    echo "       fehlt — das Zertifikats-Volume ist beschädigt."
    echo "       /etc/letsencrypt aus dem Backup wiederherstellen, dann neu starten."
    exit 1
  fi

  # nginx muss waehrend der Erneuerung laufen, um die Webroot-Challenge
  # bedienen zu koennen (fruehere Versionen haben certbot ohne nginx
  # laufen lassen — echte Erneuerungen konnten daher nie gelingen).
  start_bg_nginx
  if [ -n "$BG_PID" ]; then
    if /usr/bin/certbot renew; then
      echo "Let's Encrypt: Erneuerungs-Check abgeschlossen."
    else
      echo "WARNING: 'certbot renew' meldete einen Fehler — es wird mit dem bestehenden Zertifikat weitergefuehrt."
    fi
  fi
  stop_bg_nginx
else
  # ---- Erststart: erstes Zertifikat beantragen ------------------------------
  # Rate-Limit-Schutz: max. ein Issuance-Versuch pro Stunde, damit ein
  # defekter Netzwerkpfad (DNS, Port 80) Let's Encrypt nicht laehmt
  # (5 fehlgeschlagene Authorizations pro Stunde = Sperre fuer die Domain).
  NOW=$(date +%s)
  SKIP=0
  if [ -f "$ATTEMPT_FILE" ]; then
    LAST=$(cat "$ATTEMPT_FILE" 2>/dev/null)
    case "$LAST" in
      "" | *[!0-9]*) LAST=0 ;;
    esac
    if [ $((NOW - LAST)) -lt 3600 ]; then
      SKIP=1
      echo "Let's Encrypt: Issuance-Versuch uebersprungen (letzter Versuch < 60 Min. her — Rate-Limit-Schutz)."
    fi
  fi

  if [ "$SKIP" -eq 0 ]; then
    date +%s > "$ATTEMPT_FILE"
    start_bg_nginx
    if [ -n "$BG_PID" ]; then
      sleep 1
      if /usr/bin/certbot certonly -n --webroot -w "$WEBROOT" --email "$EMAIL" -d "$DOMAIN" --rsa-key-size 4096 --agree-tos --force-renewal; then
        echo "Let's Encrypt: Zertifikat fuer $DOMAIN erfolgreich beantragt."
      else
        echo "ERROR: Let's-Encrypt-Issuance fehlgeschlagen (DNS-Eintrag aktuell? Port 80 aus dem Internet erreichbar?)"
        echo "       nginx startet mit dem Dummy-Zertifikat — Problem beheben und"
        echo "       den Container neu starten, um es erneut zu versuchen (max. 1x/Stunde)."
      fi
    else
      echo "ERROR: Keine Issuance moeglich — Hintergrund-nginx laeuft nicht."
    fi
    stop_bg_nginx
  fi
fi

# START NGINX IN FOREGROUND AND RUN FOREVER
nginx -g 'daemon off;'
