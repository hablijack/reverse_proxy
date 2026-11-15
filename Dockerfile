FROM nginx:1.30.4-alpine

# Sicherheitsupdates des Basis-Images einspielen, certbot (manuelle
# Issuance) + openssl (Dummy-Zertifikat im Entrypoint) installieren
RUN apk upgrade --no-cache \
 && apk add --no-cache certbot certbot-nginx openssl

# Standard-Site des nginx-Images entfernen (Welcome-Seite, antwortete auf
# beliebige Host-Header inkl. Versions-Banner)
RUN rm -f /etc/nginx/conf.d/default.conf \
 && rm -rf /usr/share/nginx/html/*

# Zertifikate: /etc/letsencrypt gehört allein certbot (Volume, im Image
# bewusst LEER — sonst kopiert Docker Inhalte ins neue Volume und certbot
# weicht auf "-0001"-Reihen aus). nginx liest /etc/nginx/ssl/, das
# select-cert beim Start verlinkt (LE-Zertifikat oder Dummy mit frischem
# Schlüssel, der nie im Repo/Image liegt).
COPY select-cert.sh /usr/local/bin/select-cert
COPY entrypoint.sh /etc/nginx/entrypoint.sh
RUN chmod 755 /usr/local/bin/select-cert /etc/nginx/entrypoint.sh \
 && mkdir -p /etc/nginx/ssl && chmod 700 /etc/nginx/ssl

# NGINX CONFIG (00-hardening.conf zuerst: globale Härtung + Catch-All)
COPY 00-hardening.conf /etc/nginx/conf.d/00-hardening.conf
COPY app.conf /etc/nginx/conf.d/app.conf
COPY bewerbung.conf /etc/nginx/conf.d/bewerbung.conf

# CREATE WEBROOT FOR CERTBOT (inkl. ACME-Challenge-Verzeichnis, das
# certbot für die HTTP-01-Challenge benötigt)
RUN mkdir -p /var/www/certbot/.well-known/acme-challenge

STOPSIGNAL SIGQUIT

CMD ["/etc/nginx/entrypoint.sh"]
