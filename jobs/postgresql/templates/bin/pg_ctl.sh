#!/bin/bash
set -x
set -e
index=<%= index %>
pg_version=<%= p("postgresql.version") %>

export LOG_FILE=/var/vcap/sys/log/postgresql/pg_server.log
export LOG_DIR=`dirname $LOG_FILE`

export PID_FILE="<%= p('postgresql.pid_file') %>"
export PID_DIR=`dirname $PID_FILE`

export PG_INSTALL_PATH=/var/vcap/packages/postgresql/${pg_version}
export PG_JOBS_PATH=/var/vcap/jobs/postgresql
export CLUSTER_PATH=/var/vcap/store/postgresql/data

export PATH=$PG_INSTALL_PATH/bin:$PATH

ha_mode="<%= p('postgresql.ha_mode') %>"
synchronous_replication="<%= p('postgresql.synchronous_replication') %>"

super_user="<%= p('postgresql.super_user.name') %>"
os_password="<%= p('postgresql.super_user.password') %>"
db_password="<%= p('postgresql.super_user.password') %>"

pg_hba=$PG_JOBS_PATH/conf/pg_hba.conf
pg_conf=$PG_JOBS_PATH/conf/postgresql.conf

pgpool_pkg_path=/var/vcap/packages/pgpool
pgpool_pkg=pgpool-II-3.5.2

primary_node=""

pg_nodes=()
<% pg_nodes = p("postgresql.hosts") %>
<% if pg_nodes != nil && pg_nodes.length > 0 then %>
     <% pg_nodes.each do |node| %>
pg_nodes=("${pg_nodes[@]}" "<%= node %>")
     <% end %>
current_node=<%= pg_nodes[index] %>
<% end %>

<% pgpool_hosts = p('pgpool.hosts') %>
pcp_host=<%= pgpool_hosts[0] %>
pcp_port=<%= p("pgpool.pcp_port") %>
pcp_user="<%= p('pgpool.pcp_user.name') %>"

archive_mode="<%= p('postgresql.archiving.archive_mode') %>"
archive_host="<%= p('postgresql.archiving.archive_host') %>"
archive_dir="<%= p('postgresql.archiving.archive_dir') %>"
archive_path="/var/vcap/store/$archive_dir"
basebackup_host="<%= p('postgresql.archiving.basebackup_host') %>"
basebackup_dir="<%= p('postgresql.archiving.basebackup_dir') %>"
basebackup_path="/var/vcap/store/$basebackup_dir"
basebackup_cron_t="<%= p('postgresql.archiving.basebackup_cron') %>"

function wait_ssh() {
	local started="false"
  	local wait_time=3
	while [ ${wait_time} -gt 0 ]
	do
		if [ ! -f /root/.ssh/authorized_keys ]; then
			echo "wait for the job of ssh."
			wait_time=$(($wait_time-1))
			sleep 2
		else
			sleep 1
			break
		fi
	done
	if [ ! -f /root/.ssh/authorized_keys ]; then
		echo "SSH is not configured, please fix it. Exit"
		exit 1
	fi
}

function init_user() {
	echo "start to init user."
	adduser $super_user sudo
	if [ `grep -c "$super_user ALL=(ALL:ALL) ALL" /etc/sudoers` -eq 0 ]; then
		echo "$super_user ALL=(ALL:ALL) ALL" >> /etc/sudoers
	fi
}
function init_dir() {
	echo "start to init dir."
	chmod -R 755 $PG_INSTALL_PATH
	chgrp -R vcap $PG_INSTALL_PATH
	if [ ! -d $LOG_DIR ]; then
    	mkdir -p $LOG_DIR
  	fi
	chown $super_user:vcap $LOG_DIR
  	if [ ! -d $PID_DIR ]; then
    	mkdir -p $PID_DIR
  	fi
  	chown $super_user:vcap $PID_DIR
  	local cluster_dir=`dirname $CLUSTER_PATH`
  	if [ ! -d $cluster_dir ]; then
    	mkdir -p $cluster_dir
    	chown $super_user:vcap $cluster_dir
  	fi
}

function init() {
	/sbin/ldconfig $PG_INSTALL_PATH/lib
	init_user
	init_dir
}

function create_cluster() {
	echo "start to create db cluster."
	local db_cluster_existed=1
	if [ ! -d $CLUSTER_PATH ]; then
		db_cluster_existed=0
	else
		if [ ! -f $CLUSTER_PATH/postgresql.conf ]; then
			db_cluster_existed=0
		else
			if [ -z "`grep $PID_FILE $CLUSTER_PATH/postgresql.conf`" ]; then
				db_cluster_existed=0
			else
				if [ -f "$CLUSTER_PATH/postmaster.pid" ]; then
					rm $CLUSTER_PATH/postmaster.pid
				fi
			fi
		fi
	fi
	if [ $db_cluster_existed -eq 0 ]; then
		su - $super_user -c "$PG_INSTALL_PATH/bin/pg_ctl initdb -D $CLUSTER_PATH"
	else
		echo "The cluster has existed already, no need to init."
		if [ -f $CLUSTER_PATH/is_primary_node ]; then
			rm $CLUSTER_PATH/is_primary_node
		fi
	fi
}

function install_pgpool_functions() {
	if ([ ! -f "$PG_INSTALL_PATH/lib/postgresql/pgpool-recovery.so" ] || [ ! -f "$PG_INSTALL_PATH/lib/postgresql/pgpool-regclass.so" ]); then
		if [ ! -z "`grep $PID_FILE $CLUSTER_PATH/postgresql.conf`"  ]; then
			cp $CLUSTER_PATH/postgresql.conf.org $CLUSTER_PATH/postgresql.conf
			if [ -f $CLUSTER_PATH/backup_label.old ]; then
				rm $CLUSTER_PATH/backup_label.old
			fi
			if [ -f $CLUSTER_PATH/recovery.conf ]; then
				rm $CLUSTER_PATH/recovery.conf
			fi
		fi
		PATH=$PG_INSTALL_PATH/bin:$PATH
		tar xzf ${pgpool_pkg_path}/${pgpool_pkg}.tar.gz -C ${pgpool_pkg_path}/
		cd ${pgpool_pkg_path}/${pgpool_pkg}/src/sql/pgpool-recovery
		make
		make install
		chmod 644 ${pgpool_pkg_path}/${pgpool_pkg}/src/sql/pgpool-recovery/pgpool-recovery.sql
		cd ${pgpool_pkg_path}/${pgpool_pkg}/src/sql/pgpool-regclass
		make
		make install
		chmod 644 ${pgpool_pkg_path}/${pgpool_pkg}/src/sql/pgpool-regclass/pgpool-regclass.sql
		su - $super_user -c "$PG_INSTALL_PATH/bin/pg_ctl start -D $CLUSTER_PATH"
		sleep 3
		su - $super_user -c "$PG_INSTALL_PATH/bin/psql -f ${pgpool_pkg_path}/${pgpool_pkg}/src/sql/pgpool-recovery/pgpool-recovery.sql template1"
		su - $super_user -c "$PG_INSTALL_PATH/bin/psql -f ${pgpool_pkg_path}/${pgpool_pkg}/src/sql/pgpool-recovery/pgpool-recovery.sql postgres"
		su - $super_user -c "$PG_INSTALL_PATH/bin/psql -f ${pgpool_pkg_path}/${pgpool_pkg}/src/sql/pgpool-regclass/pgpool-regclass.sql template1"
		su - $super_user -c "$PG_INSTALL_PATH/bin/psql -f ${pgpool_pkg_path}/${pgpool_pkg}/src/sql/pgpool-regclass/pgpool-regclass.sql postgres"
		su - $super_user -c "$PG_INSTALL_PATH/bin/pg_ctl stop -m fast -D $CLUSTER_PATH"	
	fi
}

function conf_cluster() {
	cp $pg_hba $CLUSTER_PATH/pg_hba.conf
	chown $super_user:$super_user $CLUSTER_PATH/pg_hba.conf
	chmod 600 $CLUSTER_PATH/pg_hba.conf

	if [ ! -f $CLUSTER_PATH/postgresql.conf.org ]; then
		cp $CLUSTER_PATH/postgresql.conf $CLUSTER_PATH/postgresql.conf.org
		chown $super_user:$super_user $CLUSTER_PATH/postgresql.conf.org
		chmod 600 $CLUSTER_PATH/postgresql.conf.org
	fi
	cp $pg_conf $CLUSTER_PATH/postgresql.conf
	chown $super_user:$super_user $CLUSTER_PATH/postgresql.conf
	chmod 600 $CLUSTER_PATH/postgresql.conf

	echo "Copy pgpool online recovery scripts to PG cluster directory."
	cp $PG_JOBS_PATH/bin/recovery_1st_stage.sh $CLUSTER_PATH
	cp $PG_JOBS_PATH/bin/pgpool_remote_start $CLUSTER_PATH
	chmod 755 $CLUSTER_PATH/recovery_1st_stage.sh
	chmod 755 $CLUSTER_PATH/pgpool_remote_start
}

function get_primary_node() {
	local is_primary_node=""
	local is_primary_node_running=""
	set +e
	for pg_node in "${pg_nodes[@]}"
	do
		if [ "${current_node}" == "${pg_node}" ]; then 
			continue
		fi
		is_primary_node=`ssh ${pg_node} "test -f $CLUSTER_PATH/is_primary_node && echo 'true' || echo 'false'"`
		if [ "${is_primary_node}" == "true" ]; then
			is_primary_node_running=`ssh ${pg_node} "test -f $CLUSTER_PATH/postmaster.pid && echo 'true' || echo 'false'"`
			if [ "${is_primary_node_running}" == "true" ]; then
				primary_node=$pg_node
				break
			else
				continue
			fi
		fi
	done
	set -e
}

function start_as_primary() {
	su - $super_user -c "$PG_INSTALL_PATH/bin/pg_ctl start -D $CLUSTER_PATH"
	wait_time=3
	while [ ${wait_time} -gt 0 ]
		do
			if [ -f $CLUSTER_PATH/postmaster.pid ]; then
				echo "The postgresql server is running, generate a flag file \"is_primary_node\"."
				su - $super_user -c "touch $CLUSTER_PATH/is_primary_node"
				break
			else
				echo "The postgresql server is not started yet, wait 2 seconds until it is running."
				wait_time=$(($wait_time-1))
				sleep 2
			fi
		done
	if [ ! -f $CLUSTER_PATH/postmaster.pid ]; then
		echo "The postgresql server started failed."
		exit 2 
	fi 
}

function start_as_standby() {
	sleep 5 #sleep 5 seconds, wait pgpool get another pg node as primary node.
	local is_pgpool_running=`ssh ${pcp_host} 'kill -0 $(cat /var/vcap/sys/run/pgpool/pgpool.pid)>/dev/null && echo "true" || echo "false"'`
	local pgnode_index=""
	if [ -f $CLUSTER_PATH/pgnode_index ]; then
		pgnode_index=`cat $CLUSTER_PATH/pgnode_index`
	fi
	if [ "${is_pgpool_running}" == "true" ]; then
		echo "pgpool is running, call pcp command to recover myself as a standby node."
		if [ ! -z "${pgnode_index}" ]; then
			ssh ${pcp_host} "export PCPPASSFILE=/var/vcap/jobs/pgpool/conf/.pcppass && $pgpool_pkg_path/bin/pcp_recovery_node -h $pcp_host -p $pcp_port -U $pcp_user -w $pgnode_index"
		else
			echo "The index of pg node index is unknown, please check pgpool log file on pgpool host and figure out why pgpool did not assign index number to this pg node."
			exit 3
		fi
	else
		echo "pgpool status is unknown."
		if [ ! -z "${pgnode_index}" ]; then
			echo "The index of pg node has been assigned by pgpool, but pgpool is not running. Please check pgpool log file on pgpool host and figure out why pgpool is not running."
			exit 4
		else
			echo "pgpool is NOT running, start myself as a standby node."
			sleep 3 #sleep 3 seconds, wait pgpool get another pg node as primary node.
			local recovery_1st_stage_done=`ssh $super_user@$primary_node "$CLUSTER_PATH/recovery_1st_stage.sh $CLUSTER_PATH $current_node $CLUSTER_PATH > /dev/null && echo true || echo false"`
			if [ "${recovery_1st_stage_done}" == "true" ]; then
				su - $super_user -c "$PG_INSTALL_PATH/bin/pg_ctl start -D $CLUSTER_PATH"
				sleep 5
			else
				echo "The recovery_1st_stage script is failed on primary node, please check the log."
				exit 3
			fi
		fi
	fi
}

function set_synchronous_standby_names_on_primary() {
	if [ $synchronous_replication == true ]; then
		echo "Try to set property synchronous_standby_names on primary node."
		local set_names=`ssh $super_user@$primary_node "$PG_JOBS_PATH/bin/pg_debugger set_synchronous_standby_names_on_primary \
		 $PG_JOBS_PATH/bin/set_synchronous_standby_names_on_primary.sh $current_node $CLUSTER_PATH \
		 && echo true || echo false"`
		 if [ $set_names == "false" ]; then
		 	echo "Failed to insert current node into synchronous_standby_names property on primary, please check log file on primary node."
		 	echo "The replication mode is ASYNCHRONOUS $ha_mode."
		 fi
	fi
}

function set_archive() {
	if [ "$archive_mode" == "on" ]; then
		ssh $archive_host "test -d $archive_path || (mkdir -p $archive_path && chown $super_user:vcap $archive_path)"
		ssh $basebackup_host "test -d $basebackup_path || (mkdir -p $basebackup_path && chown $super_user:vcap $basebackup_path)"
	fi
}

function start_server() {
	if [ $ha_mode == "stream" ]; then
		get_primary_node
		set_archive
		if [ -z ${primary_node} ]; then
			start_as_primary
		else
			start_as_standby
			set_synchronous_standby_names_on_primary
		fi
	else
		echo "Other HA mode is not supported, please use \"stream\" as HA mode to deploy."
		exit 5
	fi
}

function basebackup_cron() {
	local remove="false"
	if [ "$archive_mode" == "on" ]; then
		if [ ! -z "${basebackup_cron_t}" ]; then
			if [ -z "$(crontab -l | grep "$PG_JOBS_PATH/bin/basebackup.sh")" ]; then
				local cron_command="su - pgsql -c \"$PG_JOBS_PATH/bin/pg_debugger basebackup $PG_JOBS_PATH/bin/basebackup.sh\""
				local cron_job="${basebackup_cron_t} ${cron_command}"
				crontab -l > $LOG_DIR/mycron
				echo "${cron_job}" >> $LOG_DIR/mycron
				crontab $LOG_DIR/mycron
				rm $LOG_DIR/mycron
			fi
		else
			remove="true"
		fi
	else
		remove="true"
	fi
	if [ "$remove" == "true" ]; then
		crontab -l | grep -v "$PG_JOBS_PATH/bin/basebackup.sh" | crontab -
	fi
}

case "$1" in
	'start')
	  wait_ssh
	  init
	  create_cluster
	  install_pgpool_functions
	  conf_cluster
	  start_server
	  basebackup_cron
	;;
	'stop')
		set +e
	  	su - $super_user -c "$PG_INSTALL_PATH/bin/pg_ctl stop -m fast -D $CLUSTER_PATH"
	  	sleep 3
	  	crontab -l | grep -v "$PG_JOBS_PATH/bin/basebackup.sh" | crontab -
	;;
esac
