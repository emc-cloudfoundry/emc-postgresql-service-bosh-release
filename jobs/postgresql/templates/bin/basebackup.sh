#!/bin/bash

## This script should be run as the super user of Postgresql
set -e
pg_version=<%= p("postgresql.version") %>

basebackup_host="<%= p('postgresql.archiving.basebackup_host') %>"
basebackup_dir="<%= p('postgresql.archiving.basebackup_dir') %>"
basebackup_path="/var/vcap/store/$basebackup_dir"

ha_mode="<%= p('postgresql.ha_mode') %>"

PID_FILE="<%= p('postgresql.pid_file') %>"
PID_DIR=`dirname $PID_FILE`

PG_INSTALL_PATH=/var/vcap/packages/postgresql/${pg_version}
PG_JOBS_PATH=/var/vcap/jobs/postgresql
CLUSTER_PATH=/var/vcap/store/postgresql/data

PATH=$PG_INSTALL_PATH/bin:$PATH

super_user="<%= p('postgresql.super_user.name') %>"
os_password="<%= p('postgresql.super_user.password') %>"
db_password="<%= p('postgresql.super_user.password') %>"
port="<%= p('postgresql.port') %>"

is_primary=""
is_server_running=""

function is_primary_node() {
	if [ -f $CLUSTER_PATH/is_primary_node ]; then
		is_primary="true"
	else
		is_primary="false"
	fi
}

function is_server_running() {
	if [ -f $CLUSTER_PATH/postmaster.pid ]; then
		is_server_running="true"
	else
		is_server_running="false"
	fi
}
is_primary_node
is_server_running
if ([ "$is_primary" == "true" ] && [ "$is_server_running" == "true" ]); then
	wait_times=3
	while [ -f $CLUSTER_PATH/backup_label ]
		do
			if [ ${wait_times} -gt 0 ]; then
				echo "There is another backup is running, wait 2 second for it's done."
				wait_times=$(($wait_times-1))
				sleep 2
			else
				echo "Already waited for 6 seconds, but the other backup process is still running, please check!"
				exit 2
			fi
		done
	$PG_INSTALL_PATH/bin/psql -p $port -c "SELECT pg_start_backup('basebackup', true)" postgres
	set +e
	time_stamp=$(date +"%s")
	backup_file_not_exist=`ssh $basebackup_host "test ! -d $basebackup_path/$time_stamp && test ! -f $basebackup_path/${time_stamp}.tgz" && echo "true" || echo "false"`
	if [ "$backup_file_not_exist" == "true" ]; then
		ssh $basebackup_host "mkdir -p $basebackup_path/$time_stamp"

		sync_data_dir_successful=0
		rsync -C -a --delete -e ssh --exclude postmaster.pid \
		--exclude postmaster.opts --exclude pg_log --exclude pg_xlog \
		$CLUSTER_PATH/ $super_user@$basebackup_host:$basebackup_path/$time_stamp \
		&& sync_data_dir_successful=1 || sync_data_dir_successful=0

		if [ $sync_data_dir_successful -eq 1 ]; then
			zip_succ=`ssh $basebackup_host "tar -C $basebackup_path -czf $basebackup_path/${time_stamp}.tgz $time_stamp" && echo "true" || echo "false"`
			if [ "$zip_succ" == "true" ]; then			
				ssh $basebackup_host "rm -rf $basebackup_path/$time_stamp"
			fi
		fi

		$PG_INSTALL_PATH/bin/psql -p $port -c "SELECT pg_stop_backup()" postgres
		if [ $sync_data_dir_successful -eq 0 ]; then
			echo "Base backup to $basebackup_host failed, because cannot sync database directory."
			exit 4
		fi 
	else
		echo "The base backup file \"$time_stamp\" at $basebackup_path on $basebackup_host already exists, please check."
		exit 3
	fi
else
	echo "This is not primary node, or the server is not running."
	exit 1
fi
