#!/bin/bash
# This script will be only run at primary node ONLY IF "synchronous_replication" is true in deployment manifest. 
# When the standby node is started, it should be register itself into "synchronous_standby_names" on primary node.
# This script should be run as database super_user
set -x
set -e

application_name=$1
cluster_path=$2

pg_version=<%= p("postgresql.version") %>
export PG_INSTALL_PATH=/var/vcap/packages/postgresql/${pg_version}

if [ -z $application_name ]; then
	echo "Application name cannot be empty."
	exit 1
fi
if [ -z $cluster_path ]; then
	echo "Cluster path cannot be empty."
	exit 1
fi

echo "Try to set property synchronous_standby_names on primary node."

if [ -z "`grep "synchronous_standby_names" $cluster_path/postgresql.conf`" ]; then
	synchronous_standby_names="synchronous_standby_names = '$application_name'"
	echo $synchronous_standby_names >> $cluster_path/postgresql.conf
else
	synchronous_standby_names=`grep "synchronous_standby_names" $cluster_path/postgresql.conf`
	app_names_str=`echo $synchronous_standby_names | cut -d"'" -f2`
	IFS=',' read -ra app_names <<< $app_names_str
	for name in "${app_names[@]}"; do
		if [ $application_name == $name ]; then
			echo "This standby node $name is existing in synchronous_standby_names property."
			exit 0
		fi
	done
	new_synchronous_standby_names="synchronous_standby_names = "\'$app_names_str,$application_name\'
	sed -i '/synchronous_standby_names/d' $cluster_path/postgresql.conf
	echo $new_synchronous_standby_names >> $cluster_path/postgresql.conf
fi
$PG_INSTALL_PATH/bin/pg_ctl reload -D $cluster_path \
&& exit 0 \
|| echo "Failed to load postgresql.conf, because of inserting new synchronous standby names."
exit 3