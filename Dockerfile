FROM nginx:1.27.5-alpine

# INSTALL CERTBOT
RUN apk add certbot certbot-nginx

# ADD DUMMY CERTS
RUN mkdir -p /etc/letsencrypt/live/garden.dedyn.io
COPY dummy_certs/* /etc/letsencrypt/live/garden.dedyn.io/

# ADD ENTRYPOINT SCRIPT
COPY entrypoint.sh /etc/nginx/entrypoint.sh
RUN chmod a+x /etc/nginx/entrypoint.sh

# NGINX CONFIG
COPY app.conf /etc/nginx/conf.d/app.conf

# CREATE WEBROOT FOR CERTBOT
RUN mkdir -p /var/www/certbot

CMD ["/etc/nginx/entrypoint.sh"]
