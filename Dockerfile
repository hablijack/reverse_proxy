FROM nginx:1.30.4-alpine

# INSTALL CERTBOT
RUN apk add certbot certbot-nginx

# ADD DUMMY CERTS
# - /etc/letsencrypt/live/... : bei einem LEEREN Volume von Docker in das
#   Volume kopiert (Erststart).
# - /opt/dummy-certs/ : sichere Kopie, die NICHT vom /etc/letsencrypt-Volume
#   verdeckt wird — der Entrypoint stellt daraus das Zertifikat wieder her,
#   wenn das Volume leer/beschädigt ist.
RUN mkdir -p /etc/letsencrypt/live/garden.dedyn.io /opt/dummy-certs
COPY dummy_certs/* /etc/letsencrypt/live/garden.dedyn.io/
COPY dummy_certs/* /opt/dummy-certs/

# ADD ENTRYPOINT SCRIPT
COPY entrypoint.sh /etc/nginx/entrypoint.sh
RUN chmod a+x /etc/nginx/entrypoint.sh

# NGINX CONFIG
COPY app.conf /etc/nginx/conf.d/app.conf
COPY bewerbung.conf /etc/nginx/conf.d/bewerbung.conf

# CREATE WEBROOT FOR CERTBOT
RUN mkdir -p /var/www/certbot

CMD ["/etc/nginx/entrypoint.sh"]
