#!/bin/bash
# Recovery script for streaming replication.
set -x
set -e
pg_version=<%= p("postgresql.version") %>
db_user="<%= p('postgresql.super_user.name') %>"
primaryhost=`ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/'`
port="<%= p('postgresql.port') %>"
<% hosts = p('postgresql.hosts') %>
<% if hosts != nil && hosts.length > 0 then %>
primaryhost=<%= hosts[index] %>
<% end %>

LOG_FILE=/var/vcap/sys/log/postgresql/pg_server.log
PG_INSTALL_PATH=/var/vcap/packages/postgresql/${pg_version}

case "$1" in
	'recovery_1st_stage')
		datadir=$2
		desthost=$3
		destdir=$4
		echo "datadir=${datadir}"
		echo "desthost=${desthost}"
		echo "destdir=${destdir}"
		date_str=$(date +"%s")
		wait_times=3
		while [ -f $datadir/backup_label ]
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
		$PG_INSTALL_PATH/bin/psql -p $port -c "SELECT pg_start_backup('stream_replication', true)" postgres
		set +e
		sync_data_dir_successful=0
		rsync -C -a --delete -e ssh --exclude postgresql.conf --exclude postmaster.pid \
		--exclude postmaster.opts --exclude pg_log --exclude pg_xlog \
		--exclude recovery.conf --exclude recovery.done \
		--exclude is_primary_node --exclude pgnode_index \
		--exclude postgresql.conf.org \
		--exclude recovery_1st_stage.sh --exclude pgpool_remote_start \
		$datadir/ $db_user@$desthost:$destdir \
		&& sync_data_dir_successful=1 || sync_data_dir_successful=0

		if [ $sync_data_dir_successful -eq 1 ]; then
			ssh $db_user@$desthost "/var/vcap/jobs/postgresql/bin/pg_debugger standby_recovery /var/vcap/jobs/postgresql/bin/standby_recovery.sh $destdir $primaryhost $desthost"
		fi

		$PG_INSTALL_PATH/bin/psql -p $port -c "SELECT pg_stop_backup()" postgres
		if [ $sync_data_dir_successful -eq 0 ]; then
			echo "Online recovery for $desthost failed, because cannot sync backup."
			exit 3
		fi 
	;;
	'remote_start')
		desthost=$2
		destdir=$3
		echo "desthost=${desthost}"
		echo "destdir=${destdir}"
		ssh $db_user@$desthost "$PG_INSTALL_PATH/bin/pg_ctl start -D $destdir -l $LOG_FILE"
	;;
esac