#!/bin/bash
## This script must be run by the user who inited the db cluster, but not root
set -x
set -e
pg_version=<%= p("postgresql.version") %>
LOG_FILE=/var/vcap/sys/log/postgresql/pg_server.log
LOG_DIR=`dirname $LOG_FILE`

export PG_INSTALL_PATH=/var/vcap/packages/postgresql/${pg_version}
export PG_JOBS_PATH=/var/vcap/jobs/postgresql
export CLUSTER_PATH=/var/vcap/store/postgresql/data

super_user="<%= p('postgresql.super_user.name') %>"
if [ $USER != $super_user ]; then
	echo "This script must be run by the user who inited the db cluster, but not others"
	exit 2
fi

echo "Start postgresql server."
$PG_INSTALL_PATH/bin/pg_ctl start -D $CLUSTER_PATH -l $LOG_FILE

wait_time=3
while [ ${wait_time} -gt 0 ]
	do
		if [ -f $CLUSTER_PATH/postmaster.pid ]; then
			echo "The postgresql server is running, generate a flag file \"is_primary_node\"."
			touch $CLUSTER_PATH/is_primary_node
			exit 0
		else
			echo "The postgresql server is not started yet, wait 2 seconds until it is running."
			wait_time=$(($wait_time-1))
			sleep 2
		fi
	done
if [ ! -f $CLUSTER_PATH/postmaster.pid ]; then
	echo "The postgresql server started failed."
	exit 1
fi 