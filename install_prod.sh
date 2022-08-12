#!/bin/bash

set -e

# Install the dependency packages
if ! [ -x "$(command -v dos2unix)" ]; then
  apt-get update && apt-get install -y dos2unix
fi
if ! [ -x "$(command -v curl)" ]; then
  apt-get update && apt-get install -y curl
fi

if [ -f .env ]; then
  dos2unix .env
  source .env
else
  echo ".env file not found"
  exit 1
fi

find . -type f -name "*.sh" -exec dos2unix {} +
find . -type f -name "*.sh" -exec chmod +x {} +

# Replace domain/server name in the common files.
sed -i "s/{{DOMAIN_NAME}}/$DOMAIN_NAME/g" \
  conf/nginx/*.conf \
  common/init-letsencrypt.sh
sed -i "s/{{SERVER_NAME}}/$SERVER_NAME/g" \
  common/deploy-github-key.sh \
  common/dockerpull.sh \
  common/gitpull.sh \
  common/init-letsencrypt.sh \
  common/conf_s3.sh

# Configuring scw cli and s3 
./common/conf_s3.sh

if [[ "${SERVER_NAME}" == *"odoo"* ]];then
  sed -i "s/{{DB_USERNAME}}/$DB_USERNAME/g" common/postgres_backup.sh
  sed -i "s/{{DB_NAME}}/$ODOO_DB_NAME/g" common/postgres_backup.sh
  sed -i "s/{{SERVER_NAME}}/$SERVER_NAME/g" common/postgres_backup.sh
  sed -i "s/{{SERVER_NAME}}/$SERVER_NAME/g" common/retention.json
else
  sed -i "s/{{DB_USERNAME}}/$DB_USERNAME/g" common/postgres_backup.sh
  sed -i "s/{{DB_NAME}}/$DB_DATABASE/g" common/postgres_backup.sh
  sed -i "s/{{SERVER_NAME}}/$SERVER_NAME/g" common/postgres_backup.sh
  sed -i "s/{{SERVER_NAME}}/$SERVER_NAME/g" meveo-common/cron.conf meveo-common/meveo_backup_restore.sh
  sed -i "s/{{SERVER_NAME}}/$SERVER_NAME/g" common/retention.json
  ./meveo-common/meveo_backup_restore.sh cron_setup
fi

# Check what is the local distribution
if [ -f /etc/os-release ]; then
  # freedesktop.org and systemd
  . /etc/os-release
  OS=$NAME
  VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
  # linuxbase.org
  OS=$(lsb_release -si)
  VER=$(lsb_release -sr)
fi
echo "OS = $OS."

# Docker installation
if ! [ -x "$(command -v docker)" ]; then
  echo "Installing docker ..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
fi
docker --version

# Docker-compose installation
if ! [ -x "$(command -v docker-compose)" ]; then
  echo "Installing docker-compose"
  curl -L https://github.com/docker/compose/releases/download/1.29.2/docker-compose-Linux-x86_64 -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi
docker-compose --version

# Sergent installation
if ! pgrep -x "sergent" > /dev/null; then
  echo "Sergent is not running."

  if ! [ -x "$(command -v sergent)" ]; then
    echo "Sergent not installed. Installing ..."
    docker pull manaty/sergent
    docker run --rm --entrypoint cat manaty/sergent /work/application > /usr/local/bin/sergent
    chmod +x /usr/local/bin/sergent
  fi

  if [ ! -f "/lib/systemd/system/sergent.service" ]; then
    SERGENT_PORT=${SERGENT_PORT:-8081}

    echo "sergent.service creating..."
    cat > /lib/systemd/system/sergent.service << EOF
[Unit]
Description=Sergent Service
After=network.target

[Service]
ExecStart=/bin/sh -c 'export SERGENT_COMMAND_PATH=/home/${SERVER_NAME}/common; \
    /usr/local/bin/sergent \
    -Dquarkus.http.host=0.0.0.0 \
    -Dquarkus.http.port=${SERGENT_PORT} > /var/log/sergent.log 2>&1'
KillMode=process
Restart=on-failure
Type=simple

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable sergent.service
    echo "sergent.service installed."
  fi
  systemctl start sergent.service
  echo "sergent.service started."
fi

# Move to the directory in where docker-compose.yml is located.
cd /home/$SERVER_NAME

# Add odoo_addons at home directory
if [[ "${SERVER_NAME}" == *"odoo"* ]] && [[ "$1" != "odoo_reset" ]];then
  cd odoo-common
  ./odoo_addons.sh
  cd ..
elif [[ "${SERVER_NAME}" == *"odoo"* ]] && [[ "$1" == "odoo_reset" ]];then
        cd odoo-common
       	if [[ -z "$2" ]] || [[ -z "$3" ]];then
          echo "Git Username or Passkey has not been provided"
        else
          ./odoo_addons.sh pull all $2 $3
          ./home/$SERVER_NAME/common/postgres_backup.sh backup s3-push
          docker-compose restart odoo
        fi
	cd ..
fi

echo
if [[ "${SERVER_NAME}" == *"odoo"* ]] && [[ "$1" = "new_odoo_version" ]];then
  if [[ -z "$2" ]];then
     echo "New Odoo Docker version not supplied"
  else
     echo " Creating new ODOO version containers"
     ./odoo-common/odoo_docker_pull.sh $2
     a=$(sed -n '/ODOO_VERSION/p' .env) && sed -i "s/$a/ODOO_VERSION=$2/" .env
     echo y | docker-compose rm -s -v odoo
  fi
fi
echo "Starting containers ..."
docker-compose up -d
echo

# Grant access to meveo user for postgres schema update
docker exec postgres psql -U meveo -c "grant insert, update, delete on all tables in schema public to meveo;"

# If SSL cert file doesn't exist, do init-letsencrypt.
if [ ! -f "conf/certbot/conf/live/$DOMAIN_NAME/privkey.pem" ]; then
  ./common/init-letsencrypt.sh
  sleep 3
fi

echo "Reloading nginx ..."
docker-compose exec -t nginx nginx -s reload
echo

if [[ "${SERVER_NAME}" != *"odoo"* ]];then
# Create Wildfly Console admin user
docker exec -it meveo ./bin/add-user.sh $WILDFLY_ADMIN_ID $WILDFLY_ADMIN_PASS --silent
fi

if [[ "${SERVER_NAME}" == *"odoo"* ]];then
 echo "Installing odoo module"
 POSTGRES_IP= docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' postgres
 docker exec -t -d odoo /usr/bin/odoo -p 8070 --db_host=$POSTGRES_IP --db_user=$DB_USERNAME --db_password=$DB_PASSWOR -d $DB_DATABASE -u odoo_marketplace,odoo-telecelplay-marketplace,marketplace_shipping_per_product,shipping_per_product,payment_liquichain_official
fi

# Setup server_backup cron
grep -qF "0 1 * * * root /bin/bash /home/$SERVER_NAME/common/server_backup.sh" /etc/crontab || (sed -i '8 s/$/:\/home\/'"$SERVER_NAME"'\/common\/server_backup.sh/' -i /etc/crontab && echo "0 1 * * * root /bin/bash /home/$SERVER_NAME/common/server_backup.sh" >> /etc/crontab)

# Setup postgres_backup cron
grep -qF "0 2 * * * root /bin/bash /home/$SERVER_NAME/common/postgres_backup.sh" /etc/crontab || (sed -i '8 s/$/:\/home\/'"$SERVER_NAME"'\/common\/postgres_backup.sh/' -i /etc/crontab && echo "0 2 * * * root /bin/bash /home/$SERVER_NAME/common/postgres_backup.sh backup s3-push" >> /etc/crontab)

# Revoke access from meveo user for postgres schema update
docker exec postgres psql -U meveo -c "revoke insert, update, delete on all tables in schema public from meveo;"

echo "Everything installed."
