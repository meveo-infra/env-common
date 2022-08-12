#!/bin/bash -e
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/{{SERVER_NAME}}/odoo-common/postgres_backup.sh
. /etc/profile

postgres_dump_path="/home/postgres_dump"
#server=$(awk '{print substr($0, 10)}' <<< env-odoo-staging)

if [ "$1" = "backup" ]; then
        mkdir -p $postgres_dump_path
        docker exec -t postgres pg_dump -c -U {{DB_USERNAME}} -d {{DB_NAME}} > $postgres_dump_path/postgres_latest_dump.sql
        if [ "$2" = "s3-push" ];then
                if s3cmd ls "s3://{{SERVER_NAME}}-postgres-backup" 2>&1 | grep -q 'NoSuchBucket';then
                     s3cmd mb s3://{{SERVER_NAME}}-postgres-backup
                fi
                s3cmd setlifecycle retention.json s3://{{SERVER_NAME}}-postgres-backup
                s3cmd -c /root/.s3cfg put $postgres_dump_path/postgres_latest_dump.sql s3://{{SERVER_NAME}}-postgres-backup/postgres_latest_dump_`date +%d%b%Y%H%M%S`.sql
        fi
elif [ "$1" = "restore" ]; then
        docker cp $postgres_dump_path/postgres_latest_dump.sql postgres:/postgres_latest_dump.sql
        docker exec postgres psql -U {{DB_USERNAME}} -d {{DB_NAME}} -f postgres_latest_dump.sql
else
        echo "Please provide argument to postgres_backup_cron.sh as 'backup' or 'restore' only"
fi
