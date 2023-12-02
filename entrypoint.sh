#!/bin/sh

# MANAGE LETSENCRYPT
DIR="/etc/letsencrypt/archive"
#if [ -d "$DIR" ]; then
  # RENEW CERTIFICATES
  #/usr/bin/certbot renew
#else
  # START NGINX IN BACKGROUND
  #/usr/sbin/nginx

  # INITIALIZE LETSENCRYPT
  #rm -rf /etc/letsencrypt/live
  #/usr/bin/certbot certonly -n --webroot -w /var/www/certbot --email christoph.habel@posteo.de -d greenhouse.home-webserver.de --rsa-key-size 4096 --agree-tos --force-renewal

  # STOP BACKGROUND NGINX PROCESS
  #killall nginx
fi

# START NGINX IN FOREGROUND AND RUN FOREVER
nginx -g 'daemon off;'
