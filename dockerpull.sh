#!/bin/bash -e

cd /home/{{SERVER_NAME}}
docker-compose pull
chmod +x ./common/install.sh
if [ $# -eq 0 ];then
  ./common/install.sh
elif [ "$1" = "new_odoo_version" ]; then
  if [[ -z "$2" ]];then
     echo "New Odoo Docker version not supplied"
  else
     ./common/install.sh $1 $2
  fi
fi
