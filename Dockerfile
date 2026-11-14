FROM nginx:1.30.4-alpine

# Sicherheitsupdates des Basis-Images einspielen, certbot (manuelle
# Issuance) + openssl (Dummy-Zertifikat im Entrypoint) installieren
RUN apk upgrade --no-cache \
 && apk add --no-cache certbot certbot-nginx openssl

# Standard-Site des nginx-Images entfernen (Welcome-Seite, antwortete auf
# beliebige Host-Header inkl. Versions-Banner)
RUN rm -f /etc/nginx/conf.d/default.conf \
 && rm -rf /usr/share/nginx/html/*

# Zertifikats-Verzeichnis anlegen. Das Dummy-Zertifikat wird NICHT mehr
# mitgeliefert, sondern beim Start mit frischem Schlüssel erzeugt
# (siehe entrypoint.sh) — ein Schlüssel im öffentlichen Repo/Image wäre
# für jeden bekannt.
RUN mkdir -p /etc/letsencrypt/live/garden.dedyn.io \
 && chmod 700 /etc/letsencrypt/live

# ADD ENTRYPOINT SCRIPT
COPY entrypoint.sh /etc/nginx/entrypoint.sh
RUN chmod 755 /etc/nginx/entrypoint.sh

# NGINX CONFIG (00-hardening.conf zuerst: globale Härtung + Catch-All)
COPY 00-hardening.conf /etc/nginx/conf.d/00-hardening.conf
COPY app.conf /etc/nginx/conf.d/app.conf
COPY bewerbung.conf /etc/nginx/conf.d/bewerbung.conf

# CREATE WEBROOT FOR CERTBOT (inkl. ACME-Challenge-Verzeichnis, das
# certbot für die HTTP-01-Challenge benötigt)
RUN mkdir -p /var/www/certbot/.well-known/acme-challenge

STOPSIGNAL SIGQUIT

CMD ["/etc/nginx/entrypoint.sh"]
