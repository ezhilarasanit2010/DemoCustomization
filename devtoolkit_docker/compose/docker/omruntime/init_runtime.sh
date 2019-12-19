#!/bin/bash
# Licensed Materials - Property of IBM
# IBM Sterling Order Management (5725-D10), IBM Order Management (5737-D18)
# (C) Copyright IBM Corp. 2018, 2019 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

set -o allexport
. /tmp/oms/.env
set +o allexport

init()
{
UPGRADE=""
if [[ $1 == "setup-upg" ]]; then
	UPGRADE="upgrade"
fi

export DPM=$(cat $RT/properties/sandbox.cfg | grep "^DATABASE_PROPERTY_MANAGEMENT=" | head -n1 | cut -d'=' -f2)
echo "DATABASE_PROPERTY_MANAGEMENT==$DPM"
cp -a /tmp/oms/system_overrides.properties ${RT}/properties
sed -i "s/DB_HOST/${DB_HOST_IMAGE}/g;s/DB_PORT/${DB_PORT_IMAGE}/g;s/DB_DATA/${DB_DATA}/g;s/DB_USER/${DB_USER}/g;s/DB_PASS/${DB_PASS}/g;s/DB_SCHEMA_OWNER/${DB_SCHEMA_OWNER}/g" ${RT}/properties/system_overrides.properties

if [[ "$DB_BACKUP_RESTORE" = "true" ]] && [[ -f "$DB_BACKUP_ZIP" ]] && [[ $1 == "setup" ]]; then
	echo "DB_BACKUP_RESTORE mode enabled. Unzipping $DB_BACKUP_ZIP to /var/oms ..." 
	cd /var/oms
	tar xzf $DB_BACKUP_ZIP
	DB_BACKUP_NAME=$(basename "$DB_BACKUP_ZIP" ".tar.gz")
	chmod -R 777 /var/oms/$DB_BACKUP_NAME
fi

echo "Waiting for DB to start (including database creation first time). You can run 'docker logs -f om-db2server' in the mean while to see the db container log..."
t=120
while [ $t -ge 0 ]; do
	if [ -f /var/oms/db.ready ]; then
		break
	else
		let t='t-1'
		sleep 10s
	fi
done
if [ $t -eq 0 ]; then
	echo "DB didn't start after 20 minutes. Check DB settings and logs at 'docker logs -f om-db2server'."
	exit 1
fi
ts=`expr 120 - $t`
tss=`expr 10 \* $ts`
echo "DB started! Took $tss seconds."
sleep 2s
mkdir -p ${RT}/tmp
cd ${RT}/bin

if [[ "$DB_BACKUP_RESTORE" = "true" ]] && [[ $1 == "setup" ]]; then
	echo "DB components already created from db backup restore.."
	./loadProperties.sh -skipdb Y -validateDBPropMgmt N
else
	if [[ $1 == setup* ]]; then
		echo "Running entitydeployer ..."
		./deployer.sh -t entitydeployer -l info -Dapplysqlonly=true
	  
		./loadProperties.sh -skipdb N -validateDBPropMgmt N
		
		echo "Loading FC..."
		cd ${RT}/repository/factorysetup && find . -name "*.restart" -exec rm -rf {} \; && cd ${RT}/bin
		./loadFactoryDefaults.sh $UPGRADE
		cd ${RT}/repository/factorysetup && find . -name "*.restart" -exec rm -rf {} \; && cd ${RT}/bin
		
		echo "Loading Views..."
		./loadCustomDB.sh $UPGRADE
	fi
fi

if [[ -f "${RT}/properties/system_overrides.properties" ]] && [[ $1 == setup* ]]; then
	echo "Loading system_overrides.properties to DB..." 
	./manageProperties.sh -mode import -file "${RT}/properties/system_overrides.properties"
fi

if [[ ${OM_INSTALL_LOCALIZATION} = "true" ]] && [[ ! -z "$OM_LOCALES" ]]; then
	echo "Setting up localization for locales - $OM_LOCALES ..."
	var=$( echo "$OM_LOCALES" | tr ',' ' ')
	for LOCALE in ""$var""
	do
		echo "Loading for locale: $LOCALE"
		./loadDefaults.sh ../repository/factorysetup/complete_installation/${LOCALE}_locale_installer.xml ../repository/factorysetup/complete_installation/XMLS
	done
	echo "Loading Language Pack translations ..."
	./sci_ant.sh -f localizedstringreconciler.xml import -Dsrc=$RT/repository/factorysetup/complete_installation/XMLS -Dbasefilename=ycplocalizedstrings
	./sci_ant.sh -f localizedstringreconciler.xml import -Dsrc=$RT/repository/factorysetup/isccs/XMLS -Dbasefilename=isccsliterals2translate
	./sci_ant.sh -f localizedstringreconciler.xml import -Dsrc=$RT/repository/factorysetup/wsc/XMLS -Dbasefilename=wscliterals2translate
	./sci_ant.sh -f localizedstringreconciler.xml import -Dsrc=$RT/repository/factorysetup/sfs/XMLS -Dbasefilename=sfsliterals2translate
fi

CUST_JAR=`echo "$(ls /tmp/oms/custjar/* 2>/dev/null)" |head -n1`
if [ ! -z "$CUST_JAR" ]; then 
	echo "Installing custommization jar $CUST_JAR ..."
    sed -i "s/DATABASE_PROPERTY_MANAGEMENT=true/DATABASE_PROPERTY_MANAGEMENT=false/g" $RT/properties/sandbox.cfg
	./InstallService.sh $CUST_JAR
	./deployer.sh -t resourcejar
	./deployer.sh -t entitydeployer -l info
    sed -i "s/DATABASE_PROPERTY_MANAGEMENT=false/DATABASE_PROPERTY_MANAGEMENT=true/g" $RT/properties/sandbox.cfg
fi
#if [[ -f "${RT}/properties/customer_overrides.properties" ]]; then
#	echo "Loading customer_overrides.properties to DB..." 
#	./manageProperties.sh -mode import -file "${RT}/properties/customer_overrides.properties"
#fi

echo "Building EARs..."
rm -rf $RT/external_deployments/*
ADDNL_OPTS=""
if [[ $AP_SKIP_ANGULAR_MINIFICATION = "true" ]]; then
	ADDNL_OPTS="$ADDNL_OPTS -Dskipangularminification=true"
fi

cd ${RT}/bin
./buildear.sh $ADDNL_OPTS -Dappserver=websphere -Dwarfiles=${AP_WAR_FILES} -Ddevmode=${AP_DEV_MODE} -Dnowebservice=true -Dnoejb=true -Dnodocear=true -Dwebsphere-profile=liberty
echo "Exploding smcfs.ear ..."
cd  ${RT}/external_deployments
mv smcfs.ear smcfs.ear1
mkdir smcfs.ear
cd smcfs.ear
$RT/jdk/bin/jar xf ../smcfs.ear1
rm -rf ../smcfs.ear1
rm -rf META_INF
if [[ ! -d lib ]]; then
	mkdir lib
	mv *.jar lib
fi
if [[ ! -z $AP_EXPLODED_WARS ]]; then
	var=$( echo "$AP_EXPLODED_WARS" | tr ',' ' ')
	cd  ${RT}/external_deployments/smcfs.ear
	for i in $var; do 
		echo "Exploding $i ..." 
		if [ -f $i ]; then 
			mv $i ${i}1 && mkdir $i && cd $i && $RT/jdk/bin/jar xf ../${i}1 && cd ../ && rm -rf ${i}1 
			#cd $i && rm -rf META-INF && mv WEB-INF/lib/* ../lib/ && cd ../
		else
			echo "$i not found. Skipping ..."
		fi
	done
fi
if [[ ! -z $AP_EXPLODED_BEJARS ]]; then
	var=$( echo "$AP_EXPLODED_BEJARS" | tr ',' ' ')
	cd  ${RT}/external_deployments/smcfs.ear/lib
	for i in $var; do 
		echo "Exploding $i ..." 
		if [ -f $i ]; then 
			mv $i ${i}1 && mkdir $i && cd $i && $RT/jdk/bin/jar xf ../${i}1 && cd ../ && rm -rf ${i}1 
		else
			echo "$i not found. Skipping ..."
		fi
	done
fi
if [[ $AP_EXPLODED_EAR != "true" ]]; then
	echo "Packing smcfs.ear ..."
	cd  ${RT}/external_deployments/smcfs.ear
	$RT/jdk/bin/jar cMf ../smcfs.ear1 *
	cd ../
	rm -rf smcfs.ear
	mv smcfs.ear1 smcfs.ear
fi

echo "Cleaning tmp directory ..."
rm -rf ${RT}/tmp/*

echo "Runtime initialized."
}

extract-rt()
{
	cd ${RT}/../
	rm -rf test /tmp/oms/runtime.tar
	mkdir -p test
	rsync -aq runtime test --exclude "tmp/*" --exclude "external_deployments/*" --exclude "installed_data/*" --exclude "repository/entitybuild/*"
	cd test/runtime
	grep -rl "${RT}" bin | xargs sed -i "s#${RT}#${1}/runtime#g"
	grep -rl "${RT}" properties | xargs sed -i "s#${RT}#${1}/runtime#g"
	grep -rl "${RT2}" bin | xargs sed -i "s#${RT2}#${1}/runtime#g"
	sed -i "s/${DB_HOST_IMAGE}/${DB_HOST}/g;s/${DB_PORT_IMAGE}/${DB_PORT}/g" properties/system_overrides.properties
	cd ../
	tar hcf /tmp/oms/runtime.tar runtime
	cd ../
	rm -rf test
}

case $1 in
	setup|setup-upg|update-extn)
		init "$1"
	;;
	extract-rt)
		extract-rt "$2"
	;;
	*)
	echo "'$1' is not a supported argument."
esac
