#!/bin/bash
# Licensed Materials - Property of IBM
# IBM Sterling Order Management (5725-D10), IBM Order Management (5737-D18)
# (C) Copyright IBM Corp. 2018, 2019 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

configure(){
	echo -e "def qcf($2) qmgr(OM_QMGR) tran(client) chan(SYSTEM.ADMIN.SVRCONN) port($4) host($3)  " > /tmp/crt_bindings.txt
	for i in {1..10}; do echo -e "define q(DEV.QUEUE.${i}) qu(DEV.QUEUE.${i}) qmgr(OM_QMGR)" >> /tmp/crt_bindings.txt ; done
	echo -e "END" >> /tmp/crt_bindings.txt

	sed -i "s|PROVIDER_URL=.*|PROVIDER_URL=file://$1|g" /opt/mqm/java/bin/JMSAdmin.config
	/opt/mqm/java/bin/JMSAdmin -v </tmp/crt_bindings.txt
	chmod 777 $1/.bindings
	
	echo "MQ Server configured successfully. Ignore any 'Unable to bind object javax.naming.NameAlreadyBoundException' errors as they mean queues already exist. "
}

update(){
	echo "Updating bindings for queue $2 ..."
	echo -e "define q($2) qu($2) qmgr(OM_QMGR)
	END" > /tmp/upd_bindings.txt
	/opt/mqm/java/bin/JMSAdmin -v  </tmp/upd_bindings.txt
	chmod 777 $1/.bindings
}

case $1 in
	configure)
		configure $2 $3 $4 $5
	;;
	update)
		update $2 $3
	;;
	*)
	echo "'$1' is not a supported argument."
esac
