#!/bin/bash -e

docker stop meveo
docker exec postgres psql -U meveo -c "update DATABASECHANGELOGLOCK set locked=false, lockgranted=null, lockedby=null where id=1;"
docker start meveo
docker restart meveo
