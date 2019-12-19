#!/bin/bash
# Licensed Materials - Property of IBM
# IBM Sterling Order Management (5725-D10), IBM Order Management (5737-D18)
# (C) Copyright IBM Corp. 2018, 2019 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

rm -rf /var/oms/db.ready

if [ -z "$DB_PASS" ]; then
  echo ""
  echo >&2 'error: DB_PASS not set'
  echo >&2 'Did you forget to add -e DB_PASS=... ?'
  exit 1
else
  echo -e "$DB_PASS\n$DB_PASS" | passwd $DB_USER
fi

if [ -z "$LICENSE" ];then
   echo ""
   echo >&2 'error: LICENSE not set'
   echo >&2 "Did you forget to add '-e LICENSE=accept' ?"
   exit 1
fi

if [ "$LICENSE" != "accept" ];then
   echo ""
   echo >&2 "error: LICENSE not set to 'accept'"
   echo >&2 "Please set '-e LICENSE=accept' to accept License before use the DB2 software contained in this image."
   exit 1
fi

if [[ "$DB_IMAGE" = "ibmcom/db2express-c" ]] && [[ "$DB_USER" != "db2inst1" ]]; then
	echo ""
	echo >&2 "error: DB_USER is not 'db2inst1'"
	echo >&2 "Only DB_USER=db2inst1 supported for $DB_IMAGE"
	exit 1
fi
  
chown -R $DB_USER:$DB_USER /home/$DB_USER/$DB_USER

su - $DB_USER -c "db2stop force"
su - $DB_USER -c "db2start"
nohup /usr/sbin/sshd -D 2>&1 > /dev/null &
  
su - $DB_USER -c "db2set DB2_CAPTURE_LOCKTIMEOUT=OFF"
su - $DB_USER -c "db2set DB2_SKIPINSERTED=ON"
su - $DB_USER -c "db2set DB2_USE_ALTERNATE_PAGE_CLEANING=ON"
su - $DB_USER -c "db2set DB2_NUM_CKPW_DAEMONS=0"
su - $DB_USER -c "db2set DB2_EVALUNCOMMITTED=ON"
su - $DB_USER -c "db2set DB2_SELECTIVITY=ON"
su - $DB_USER -c "db2set DB2_SKIPDELETED=ON"
su - $DB_USER -c "db2set DB2LOCK_TO_RB=STATEMENT"
su - $DB_USER -c "db2set DB2COMM=tcpip"
su - $DB_USER -c "db2set DB2_PARALLEL_IO=ON"
su - $DB_USER -c "db2set DB2_NUM_CKPW_DAEMONS=0"
su - $DB_USER -c "db2set DB2_COMPATIBILITY_VECTOR=ORA"
su - $DB_USER -c "db2set DB2_DEFERRED_PREPARE_SEMANTICS=NO"
su - $DB_USER -c "db2 connect to $DB_DATA"
if [ $? -ne 0 ]; then
	echo "Creating new database $DB_DATA"
    su - $DB_USER -c "db2 -x 'CREATE DATABASE $DB_DATA'"
	DB_BACKUP_NAME=$(basename "$DB_BACKUP_ZIP" ".tar.gz")
    if [ "$DB_BACKUP_RESTORE" = "true" ] && [ -d "/var/oms/$DB_BACKUP_NAME" ]; then
		echo "Restoring database $DB_DATA from /var/oms/$DB_BACKUP_NAME"
		chmod -R 777 /var/oms/$DB_BACKUP_NAME
        su - $DB_USER -c "db2 -x 'RESTORE DATABASE $DB_DATA FROM /var/oms/$DB_BACKUP_NAME REPLACE EXISTING'"
		rm -rf /var/oms/$DB_BACKUP_NAME
		echo "$DB_DATA restored...."
    else
		echo "Configuring database $DB_DATA"
        su - $DB_USER -c "db2 -x 'connect to $DB_DATA' && db2 -x 'CREATE BUFFERPOOL OMS32K_BP IMMEDIATE SIZE AUTOMATIC PAGESIZE 32k' && db2 -x 'CREATE BUFFERPOOL OMS_TMP_32K_BP IMMEDIATE SIZE AUTOMATIC PAGESIZE 32k' && db2 -x 'CREATE TABLESPACE OMS_32K_TS PAGESIZE 32k MANAGED BY AUTOMATIC STORAGE BUFFERPOOL OMS32K_BP' && db2 -x 'CREATE TEMPORARY TABLESPACE OMS_TMP_32K_TS PAGESIZE 32k MANAGED BY AUTOMATIC STORAGE BUFFERPOOL OMS_TMP_32K_BP' && db2 -x 'GRANT USE OF TABLESPACE OMS_32K_TS to public'"
        echo "$DB_DATA configured...."
    fi
fi
su - $DB_USER -c "db2 update db cfg for $DB_DATA using SELF_TUNING_MEM ON"
su - $DB_USER -c "db2 update db cfg for $DB_DATA using LOGFILSIZ 102400"
su - $DB_USER -c "db2 update db cfg for $DB_DATA using LOGPRIMARY 10"
su - $DB_USER -c "db2 update db cfg for $DB_DATA using LOGSECOND 100"
su - $DB_USER -c "db2 disconnect ALL"
su - $DB_USER -c "db2stop force"
su - $DB_USER -c "db2start"
touch /var/oms/db.ready

while true; do sleep 1000; done
