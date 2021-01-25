#!/bin/bash

# --- CONFIGURATION ---

# REPLACE TO YOUR DOMAIN NAME
DOMAIN_NAME="example.org"

# ADDING A VALID ADDRESS IS STRONGLY RECOMMENDED
EMAIL=""

# Set to 1 if you're testing your setup to avoid hitting request limits
staging=1

# ADD REQUIRED SUBDOMAINS IF NEEDED
domains=("$DOMAIN_NAME" "www.$DOMAIN_NAME")

FILES_FOR_CORRECT=(
  nginx_certbot_data/init_nginx/app.conf
  nginx_certbot_data/nginx/app.conf
)

# ----------------

if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

if [[ $DOMAIN_NAME == "example.org" || $DOMAIN_NAME == "" ]]; then
  echo 'Error: DOMAINE_NAME is not correct.' >&2
  exit 1
fi

echo "### Renaming example.org for $DOMAIN_NAME ..."
for re_file in "${FILES_FOR_CORRECT[@]}"; do
  sed -i -e "s/example.org/$DOMAIN_NAME/" $re_file
  echo "$re_file - done"
done

rsa_key_size=4096
data_path="./nginx_certbot_data/certbot"

if [ -d "$data_path" ]; then
  read -p "Existing data found for $domains. Continue and replace existing certificate? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    exit
  fi
fi

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  echo
fi

echo "### Creating dummy certificate for $domains ..."
path="/etc/letsencrypt/live/$domains"
mkdir -p "$data_path/conf/live/$domains"
docker-compose -f init-docker-compose.yml run --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot
echo


echo "### Starting nginx ..."
docker-compose -f init-docker-compose.yml up --force-recreate -d nginx
echo

echo "### Deleting dummy certificate for $domains ..."
docker-compose -f init-docker-compose.yml run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domains && \
  rm -Rf /etc/letsencrypt/archive/$domains && \
  rm -Rf /etc/letsencrypt/renewal/$domains.conf" certbot
echo


echo "### Requesting Let's Encrypt certificate for $domains ..."
#Join $domains to -d args
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

# Select appropriate email arg
case "$EMAIL" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $EMAIL" ;;
esac

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

docker-compose -f init-docker-compose.yml run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
echo

echo "### Reloading nginx ..."
docker-compose exec nginx nginx -s reload
