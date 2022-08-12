#!/bin/bash -e

cd /home/{{SERVER_NAME}}

update_submodules=""
if [ "$1" = "--submodule" ]; then
  update_submodules="--recurse-submodules"
fi

git reset --hard $update_submodules
git pull $update_submodules

if [ "$1" = "odoo-addons" ];then
 cd odoo-common
  if [[ -z "$2" ]] || [[ -z "$3" ]] || [[ -z "$4" ]] || [[ -z "$5" ]];then
    echo "Incorrect command, to git pull odoo_addons the command should be like './gitpull.sh odoo_addons pull {addon_name/all} {Git_Username} {Git_Password}'"
    exit
  else
    ./odoo_addons.sh $2 $3 $4 $5
  fi
  cd ..
fi

chmod +x ./common/install.sh
if [ $# -eq 0 ] || [ "$1" != "new_odoo_version" ];then
  ./common/install.sh
elif [ "$1" = "new_odoo_version" ]; then
  if [[ -z "$2" ]];then
     echo "New Odoo Docker version not supplied"
     exit
  else
     ./common/install.sh $1 $2
  fi
fi

if [[ "{{SERVER_NAME}}" == *"odoo"* ]];then
  chmod +x ./odoo-common/postgres_backup.sh
  ./odoo-common/postgres_backup.sh backup
fi
