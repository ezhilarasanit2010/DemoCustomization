#!/bin/bash
# Licensed Materials - Property of IBM
# IBM Sterling Order Management (5725-D10), IBM Order Management (5737-D18)
# (C) Copyright IBM Corp. 2018, 2019 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

export D=$(cd `dirname $0` && pwd)
export PD=$(dirname $D)
T=`date +%Y_%m_%d_%H_%M_%S`
set -o allexport
. $D/docker/docker-compose.properties
. $D/om-compose.properties
set +o allexport

show_license(){
	C1="$1_LICENSE"
	C2="$1_LIC"
	C3="$1_PROD"
	V1=${!C1}
	V2=${!C2}
	V3=${!C3}
	if [ "$V1" == "accept" ]; then
		echo "$C1 set to 'accept'. Accepting $V3 license silently. Proceeding ..."

	else
		echo -e "$V3 License information coming up. Press Enter to continue ..."
		read -p ""
		
		if [ "$1" == "OM" ]; then
			more $D/LICENSE.txt
		fi
		
		name="requestion"
		count=0
		while [[ "$name" = "requestion" &&  $count -lt 10 ]]
		do
		  echo -e "\n$V2 \n\nIf you accept the License Agreement, enter 'accept': "
		  read -p "" name
		  name=${name:-requestion}
		  count=$((count + 1))
		done
		
		if [ "$name" == "accept" ]; then
				echo -e "\nYou have accepted the License Agreement for $V3. Setup is proceeding ...\n\n"
				sleep 1
		else
				echo -e "\nYou have not accepted the License Agreement for $V3. Setup is exiting.\n"
				exit 1
		fi
	fi
}

if [[ $1 == setup* ]] && [[ $3 != "--accept" ]]; then
	show_license "OM"
	show_license "DB"
	show_license "AP"
	show_license "MQ"
fi

if [[ $1 == "license" ]]; then
	more $D/LICENSE.txt
	echo -e "\n$OM_LIC Press Enter to continue ..."
	read -p ""
	echo -e "\n$DB_LIC Press Enter to continue ..."
	read -p ""
	echo -e "\n$AP_LIC Press Enter to continue ..."
	read -p ""
	echo -e "\n$MQ_LIC Press Enter to continue ..."
	read -p ""
else
	mkdir -p logs
	if [ -f "logs/om-compose_${1}.log" ]; then
		mv logs/om-compose_${1}.log logs/om-compose_${1}.log.$T
	fi
	exec 1> >(tee -a logs/om-compose_${1}.log)
	exec 2>&1
fi

check_custjar()
{
	if [[ $1 = "update-extn" ]]; then
		if [ ! -f "$2" ]; then 
			echo "WARNING!!! 'update-extn' should ideally be run with a customization package. Provide a valid customization package jar as argument. E.g. - './om-compose.sh update-extn /data/om/extensions_xyzcorp_v1.0.jar'"
		fi
	fi
	rm -rf $D/docker/omruntime/custjar
	if [[ -f "$2" ]]; then 
		mkdir -p $D/docker/omruntime/custjar
		cp -a ${2} $D/docker/omruntime/custjar
	fi
}

rem_old_for_upg()
{
	rem_old_om_for_upg
	rem_old_ap_for_upg
	rem_old_ear_for_upg
	rem_old_mq_for_upg
}

rem_old_om_for_upg()
{
	echo "Removing old om-runtime contaner if exists ..."
	oorc=$(docker ps -a -f "name=om-runtime" -q)
	if [[ ! -z $oorc ]]; then
		echo "Removing old om-runtime container- $oorc..."
		docker rm om-runtime -f
	fi
	oori=$(docker images $OM_IMAGE:$OM_TAG -q)
	if [[ ! -z $oori ]]; then
		echo "Image/s of $OM_IMAGE:$OM_TAG already exist - $oori . Retagging image with current time and removing current tag ..."
		docker tag $OM_IMAGE:$OM_TAG $OM_IMAGE:${OM_TAG}_$T
		docker rmi $OM_IMAGE:$OM_TAG
	fi
}

rem_old_ap_for_upg()
{
	echo "Removing old om-appserver contaner if exists ..."
	oorc=$(docker ps -a -f "name=om-appserver" -q)
	if [[ ! -z $oorc ]]; then
		echo "Removing old om-appserver container- $oorc..."
		docker rm om-appserver -f
	fi
}

rem_old_ear_for_upg()
{
	echo "Removing old ear volume if exists..."
	docker volume rm -f docker_ear
}

rem_old_mq_for_upg()
{
	echo "Removing old om-mqserver contaner if exists ..."
	oorc=$(docker ps -a -f "name=om-mqserver" -q)
	if [[ ! -z $oorc ]]; then
		echo "Removing old om-mqserver container- $oorc..."
		docker rm om-mqserver -f
	fi
}

load_image()
{
	echo "Loading image..."
	if [[ ! "$(docker images -q $OM_IMAGE:$OM_TAG)" ]]; then
		if [[ -f "$OM_IMAGE_FILE" ]]; then
			echo "Loading image from file $OM_IMAGE_FILE ..."
			docker load --input $OM_IMAGE_FILE
		else
			echo "Could not find image file $OM_IMAGE_FILE. Checking for any ${OM_IMAGE}_*.tar.gz file in compose parent dir (latest will be picked if multiple files present)..."
			FF=$(ls -rt $PD/${OM_IMAGE}_*.tar.gz | tail -1)
			F=${FF#*${OM_IMAGE}_}
			F=${F%\.tar.gz}
			echo "Found file $FF. Tag evaluated from file to $F"
			export OM_TAG=$F
			export OM_IMAGE_FILE=$FF
			if [[ -f "$OM_IMAGE_FILE" ]]; then
				if [[ $HOST_OS = "mac" ]]; then
					sed -i "" "s|OM_TAG=.*|OM_TAG=$OM_TAG|g" $D/om-compose.properties
				else
					sed -i "s|OM_TAG=.*|OM_TAG=$OM_TAG|g" $D/om-compose.properties
				fi
				oori=$(docker images $OM_IMAGE:$OM_TAG -q)
				if [[ ! -z $oori ]]; then
					echo "Image/s of $OM_IMAGE:$OM_TAG already exist - $oori . Retagging image with current time and removing current tag ..."
					docker tag $OM_IMAGE:$OM_TAG $OM_IMAGE:${OM_TAG}_$T
					docker rmi $OM_IMAGE:$OM_TAG
				fi
				echo "Loading image from file $OM_IMAGE_FILE ..."
				docker load --input $OM_IMAGE_FILE
			fi
		fi
		if [[ ! "$(docker images -q $OM_IMAGE:$OM_TAG)" ]]; then
			echo "Error fetching OM docker image $OM_IMAGE:$OM_TAG. Check your settings for OM_TAG and tar.gz files present."
			exit 1
		else
			echo "Docker image file $OM_IMAGE_FILE loaded successfully."
		fi
    fi
}

prep_properties()
{
	cp -a $D/docker/docker-compose.properties $D/docker/.env
	echo "OM_LICENSE=accept" >> $D/docker/.env
	echo "DB_LICENSE=accept" >> $D/docker/.env
	echo "AP_LICENSE=accept" >> $D/docker/.env
	echo "MQ_LICENSE=accept" >> $D/docker/.env
	cat $D/om-compose.properties >> $D/docker/.env
	echo "" >> $D/docker/.env
	if [[ $MQ_JNDI_DIR == "../jndi" ]]; then
		export MQ_JNDI_DIR=$PD/jndi
		echo "MQ_JNDI_DIR=$MQ_JNDI_DIR" >> $D/docker/.env
	fi
	echo "MQ_JNDI_DIR2=$MQ_JNDI_DIR" >> $D/docker/.env
	cp -a $D/docker/.env $D/docker/omruntime
	if [[ $NETWORK_MODE == "host" ]]; then
        RES=$(cat $D/docker/docker-compose.yml | grep "network_mode: \"host\"")
        if [[ -z $RES ]]; then
            if [[ $HOST_OS == "mac" ]]; then
                sed -i "" "s|container_name.*|&\n    network_mode: \"host\"|g" $D/docker/docker-compose.yml
            else
                sed -i "s|container_name.*|&\n    network_mode: \"host\"|g" $D/docker/docker-compose.yml
            fi
        fi
	fi
}

start_stop()
{
	prep_properties
	cd $D/docker
	if [ ! -z $2 ]; then
		if [[ $1 != "start" ]]; then
			docker-compose stop $2
		fi
		if [[ $1 == *start ]]; then
			docker-compose start $2
		fi
	else
		if [[ $1 != "start" ]]; then
			docker-compose stop
		fi
		if [[ $1 == *start ]]; then
			docker-compose start
		fi
	fi
}

wipe_clean()
{
	prep_properties
	echo "Cleaning all volumes and containers ..."
	cd docker 
	docker-compose down -v --remove-orphans
	echo "Cleaning ${MQ_JNDI_DIR}/.bindings and temp files in compose ..."
	rm -rf .env omruntime/.env omruntime/custjar
	rm -rf ${MQ_JNDI_DIR}/.bindings
	echo "Not cleaning any extracted runtime files. Clean them manually."
}

add_queue()
{
	prep_properties
	if [ $MQ_JNDI_DIR = "../jndi" ]; then export MQ_JNDI_DIR=$PD/jndi ; fi
	docker exec -e Q=$1 om-mqserver /bin/bash -c 'echo -e "define qlocal ($Q)\nexit" | runmqsc'
	docker exec om-mqserver sh -c "/var/oms/configure_bindings.sh update $MQ_JNDI_DIR $1"
}

import_cert()
{
	if [[ ! -f $1 ]]; then
        echo "Error: Certificate/bundle file invalid. Provide full path to certificate/bundle file."
		exit 1
	fi
	validate_cert_file $1
    if [[ $? == 1 ]]; then
        exit 1
    fi
    for EXT in cer crt p12 ; do
		if [[ $1 == *.$EXT ]]; then
            cert=$(basename "$1" ".$EXT")
        fi
	done
    alias=$2
    if [[ -z $alias ]]; then
        alias=$cert
    fi
    if [[ "$cert" != "$alias" ]]; then
        echo "Either do not pass alias or rename your certificate/bundle file to conform to <alias>.cer or <alias>.crt> name, or <alias>.p12 (where alias represents the alias of the private key in the p12 bundle)"
        exit 1
    fi
    docker exec -u root:root om-appserver sh -c "chmod -R 777 /var/oms/keystore/key.jks"
    certfile=$(basename "$1")
	var=$(docker exec om-appserver sh -c "keytool -list -storepass secret4ever -keystore /var/oms/keystore/key.jks -alias $alias")
    var2=$(echo "$var" | grep "keytool error")
    if [[ -z $var ]] || [[ ! -z $var2 ]]; then
        docker cp $1 om-appserver:/tmp
        docker exec -u root:root om-appserver sh -c "chmod -R 777 /tmp/$certfile"
        if [[ $1 == *.cer ]] || [[ $1 == *.crt ]]; then
            echo "Importing certificate $certfile, alias $alias"
            docker exec om-appserver sh -c "keytool -import -storepass secret4ever -noprompt -alias $alias -keystore /var/oms/keystore/key.jks -file /tmp/$certfile"
        fi
        if [[ $1 == *.p12 ]]; then
            echo "Importing bundle file $certfile, alias $alias"
            docker exec om-appserver sh -c "keytool -importkeystore -srcstorepass secret4ever -deststorepass secret4ever -destkeystore /var/oms/keystore/key.jks -srckeystore /tmp/$certfile -srcstoretype PKCS12"
        fi
    else
        echo "Certificate $certfile, alias $alias - already exists in keystore"
    fi
	docker exec -u root:root om-appserver sh -c "rm -rf /tmp/$certfile"
}

import_one_cert()
{
	prep_properties
	if [[ "$1" == "ALL" ]]; then
        import_all_certs
	else
        import_cert $1 $2
	fi
}

import_all_certs()
{
    validate_cert_files
    find $PD/certificates -type f -print0 | while IFS= read -r -d $'\0' line; do
        import_cert $line
    done
}

validate_cert_file()
{
    if [[ $1 != *.cer ]] && [[ $1 != *.crt ]] && [[ $1 != *.p12 ]]; then
        echo "Error: File to import/remove ($1) must be a certificate of the pattern xyz.cer or xyz.crt, where xyz is the alias to be used to register to keystore. It can also be a .p12 bundle."
        return 1
    fi
}

validate_cert_files()
{
    echo "Validating certificates in $PD/certificates ..."
    cd $PD/certificates
    find . -type f -print0 | while IFS= read -r -d $'\0' line; do
        validate_cert_file $line
    done
    if [[ $? == 1 ]]; then
        exit 1
    fi
}

remove_cert()
{
	if [[ -z $1 ]]; then
        echo "Error: Certfile alias cannot be null"
		exit 1
	fi
	echo "Removing certificate alias $1"
	docker exec -u root:root om-appserver sh -c "chmod -R 777 /var/oms/keystore/key.jks"
	docker exec om-appserver sh -c "keytool -delete -storepass secret4ever -noprompt -alias $1 -keystore /var/oms/keystore/key.jks"
}

remove_one_cert()
{
	prep_properties
	if [[ "$1" == "ALL" ]]; then
        remove_all_certs
	else
        remove_cert $1
	fi
}

remove_all_certs()
{
    validate_cert_files
    find $PD/certificates -type f -print0 | while IFS= read -r -d $'\0' line; do
        alias=""
    	if [[ $line == *.cer ]]; then
	        alias=$(basename "$line" ".cer")
        fi
    	if [[ $line == *.crt ]]; then
	        alias=$(basename "$line" ".crt")
        fi
    	if [[ $line == *.p12 ]]; then
	        alias=$(basename "$line" ".p12")
        fi
        if [[ ! -z $alias ]]; then
	        remove_cert $alias            
        fi
    done
}

list_all_certs()
{
    docker exec om-appserver sh -c "keytool -list -storepass secret4ever -keystore /var/oms/keystore/key.jks"
}

extract_appman() 
{
	RT_DIR=$1
	cd $RT_DIR/bin
	rm -rf ../ApplicationManagerClient
	./sci_ant.sh -f buildApplicationManagerClient.xml
	cd ../ApplicationManagerClient
	APP_ZIP=$(ls *.zip)
	../jdk/bin/jar xf ${APP_ZIP}
}

extract_runtime() 
{
	prep_properties
	extract_rt $1
}

extract_rt() 
{
	date
	if [[ -d $1 ]]; then
		HOST_DIR=$(echo $1 | sed 's:/*$::')
	else
		HOST_DIR=$PD
	fi
	if [[ $HOST_OS = "mac" ]] && [[ -z $JAVA_HOME ]]; then
		echo "Error: JAVA_HOME not set for HOST_OS=mac"
		exit 1
	fi
	echo "Cleaning old host runtime files (renaming $HOST_DIR/runtime if exisits) ..."
	rm -rf $D/docker/omruntime/runtime.tar
	if [[ -d ${HOST_DIR}/runtime ]]; then
		mv ${HOST_DIR}/runtime ${HOST_DIR}/runtime_$T
		printf "Renamed existing host runtime directory to ${HOST_DIR}/runtime_$T. Delete this if you don't want it anymore.\n\n"
	fi
	echo "Extracting runtime files to host runtime directory $HOST_DIR/runtime ..."
	docker exec om-runtime sh -c "/tmp/oms/init_runtime.sh extract-rt ${HOST_DIR}"
	tar xf $D/docker/omruntime/runtime.tar -C ${HOST_DIR} 
	rm -rf $D/docker/omruntime/runtime.tar
	cd ${HOST_DIR}/runtime
	if [[ $HOST_OS = "mac" ]]; then
		echo "Replacing jdk from $JAVA_HOME for HOST_OS=mac ..."
		mv jdk jdku
		cp -a $JAVA_HOME jdk
		cp -a jdku/jre/lib/endorsed jdk/jre/lib
		chmod -R +x jdk/bin/ jdk/jre/bin/
	fi
	cd ${HOST_DIR}/runtime/bin
	./setupfiles.sh
	./deployer.sh -t resourcejargen
	extract_appman ${HOST_DIR}/runtime
	echo "Extracting runtime files to host runtime directory $HOST_DIR/runtime complete."
	date
}

build_and_run()
{
	date
	mkdir -p ${MQ_JNDI_DIR} $PD/certificates
	if [[ $1 == setup* ]]; then
		if [[ $4 != "--skipreload" ]]; then
			rem_old_for_upg $1
			load_image
		fi
	fi
	
	check_custjar $1 $2
	
	find . -type f -iname "*.sh" -exec chmod +x {} \;
	prep_properties
	omqc=$(docker ps -a -f "name=om-mqserver" -q)
	oorc=$(docker ps -a -f "name=om-runtime" -q)

	echo "Starting services in no-recreate mode ..."
	cd $D/docker
	if [[ ! -z $oorc ]]; then docker-compose stop omruntime; fi
	docker-compose up -d --remove-orphans --no-recreate
	docker exec -u root:root om-appserver sh -c "chown -R default:root /var/oms /opt"
	
	if [[ $1 == setup* ]]; then
        printf "\nRe-importing all certificates on setup. Ignore errors if certificates are already imported ...\n"
        import_all_certs
        printf "Certificate import finished. \n\n"
	fi
	start_stop stop appserver
	
	if [[ $1 == setup* ]] || [[ -z $omqc ]]; then
		echo "Configuring mqserver ..."
		docker exec om-mqserver sh -c "/var/oms/configure_bindings.sh configure $MQ_JNDI_DIR $MQ_CONNECTION_FACTORY_NAME $MQ_HOST $MQ_PORT"
	fi
	
	if [[ $3 != "--skip-initrt" ]]; then
		docker exec om-runtime sh -c "/tmp/oms/init_runtime.sh $1"
	fi
	printf "Setup/update complete.\n\n"
	
	start_stop start appserver
	date
	if [[ $1 == setup* ]] && [[ $SKIP_EXTRACTRT_ON_SETUP = "false" ]]; then
		extract_rt
	fi
	echo "$COMP_LOG"
}

case $1 in
	setup)
		build_and_run "setup" "$2" "$3" "$4"
	;;
	setup-upg)
		build_and_run "setup-upg" "$2" "$3" "$4"
	;;
	update-extn)
		build_and_run "update-extn" "$2" "$3"
	;;
	start|restart|stop)
		start_stop "$1" "$2"
	;;
	wipe-clean)
		wipe_clean
	;;
	add-queue)
		add_queue "$2"
	;;
	import-cert)
		import_one_cert "$2" "$3"
	;;    
	remove-cert)
		remove_one_cert "$2"
	;;      
	list-certs)
		list_all_certs
	;; 
	extract-rt)
		start_stop restart omruntime
		extract_runtime "$2"
	;;
	license)
		echo -e "\nFinished showing all license information.\n"
	;;
	*)
	prep_properties
	echo "'$1' is not a supported argument. Use: "
	echo " setup <optional:cust_jar>       Setup a fresh new docker based integrated OM environment"
	echo " setup-upg <optional:cust_jar>   Upgrade your existing environment to new images"
	echo " update-extn <cust_jar>          Update your OM environment with the latest customization jar"
	echo " extract-rt <extract_dir>        Extract a copy of runtime directory on your host machine"
	echo " start <optional: service>       Start your docker environments - all or specific service"
	echo " stop <optional: service>        Stop your docker environments - all or specific service"
	echo " restart <optional: service>     Restart your docker environments - all or specific service"
	echo " wipe-clean                      Wipes clean all your containers, including any volume data"
	echo " add-queue <queue_name>          Adds a local queue and updates your MQ bindings with the queue"
	echo " import-cert <certfile> <alias>  Import certificate providing cert file path and alias"
	echo " remove-cert <alias>             Remove certificate providing alias"
	echo " list-certs                      List all certificates currently present in the keystore"
	echo " license                         Shows the license information for various middleware images pulled"
esac
