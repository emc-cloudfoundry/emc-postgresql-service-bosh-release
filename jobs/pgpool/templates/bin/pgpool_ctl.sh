#!/bin/bash
set -x
set -e
<% pgpool_hosts = p('pgpool.hosts') %>

LOG_DIR=<%= p("pgpool.log_dir") %>
LOG_FILE=$LOG_DIR/pgpool.log
PID_FILE=<%= p('pgpool.pid_file') %>
PID_DIR=`dirname $PID_FILE`

export PGPOOL_INSTALL_PATH=/var/vcap/packages/pgpool
export PGPOOL_JOBS_PATH=/var/vcap/jobs/pgpool

pg_version=<%= p("postgresql.version") %>
export PG_INSTALL_PATH=/var/vcap/packages/postgresql/${pg_version}
export PG_JOBS_PATH=/var/vcap/jobs/postgresql
export CLUSTER_PATH=/var/vcap/store/postgresql/data

ip_address=`ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/'`
pcp_host=<%= pgpool_hosts[index] %>
pcp_port=<%= p("pgpool.pcp_port") %>

ha_mode=<%= p("postgresql.ha_mode") %>
db_user="<%= p('postgresql.super_user.name') %>"
pcp_user="<%= p('pgpool.pcp_user.name') %>"
pcp_password="<%= p('pgpool.pcp_user.password') %>"
primary_node=""

pg_nodes=()
<% pg_nodes = p("postgresql.hosts") %>
<% if pg_nodes != nil && pg_nodes.length > 0 then %>
     <% pg_nodes.each do |node| %>
pg_nodes=("${pg_nodes[@]}" "<%= node %>")
     <% end %>
<% end %>

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
		exit 4
	fi
}

function init_dir() {
	if [ ! -d $LOG_DIR ]; then
    	mkdir -p $LOG_DIR
  	fi
  	if [ ! -d $PID_DIR ]; then
    	mkdir -p $PID_DIR
  	fi
  	if [ ! -d "/var/vcap/sys/run/watchdog/" ]; then
  		mkdir -p /var/vcap/sys/run/watchdog/
  	fi
}

function install() {
	init_dir
	dpkg -i -E $PGPOOL_INSTALL_PATH/libpq5_9.3.11-0ubuntu0.14.04_amd64.deb \
		$PGPOOL_INSTALL_PATH/libpq-dev_9.3.11-0ubuntu0.14.04_amd64.deb
}

function config() {
	if [ ! -f $PGPOOL_JOBS_PATH/conf/pcp.conf ]; then
		touch $PGPOOL_JOBS_PATH/conf/pcp.conf
		chmod 644 $PGPOOL_JOBS_PATH/conf/pcp.conf
	fi
	local md5_password=`$PGPOOL_INSTALL_PATH/bin/pg_md5 $pcp_password`
	if [ `grep -c "${pcp_user}:${md5_password}" $PGPOOL_JOBS_PATH/conf/pcp.conf` -eq 0 ]; then
		echo "${pcp_user}:${md5_password}" >> $PGPOOL_JOBS_PATH/conf/pcp.conf
	fi

	if [ ! -f $PGPOOL_JOBS_PATH/conf/.pcppass ]; then
		touch $PGPOOL_JOBS_PATH/conf/.pcppass
		chmod 600 $PGPOOL_JOBS_PATH/conf/.pcppass
	fi
	echo "${pcp_host}:${pcp_port}:${pcp_user}:${pcp_password}" > $PGPOOL_JOBS_PATH/conf/.pcppass
	export PCPPASSFILE=$PGPOOL_JOBS_PATH/conf/.pcppass
	echo "export PCPPASSFILE=$PGPOOL_JOBS_PATH/conf/.pcppass" >> /etc/profile
	echo "set pcp pass file: echo PCPPASSFILE=${PCPPASSFILE}"
}

function config_rsyslog() {
	if ([ -f "/etc/rsyslog.d/50-default.conf" ] && [ ! -f "/etc/rsyslog.d/50-default.conf.bak" ]); then
		cp /etc/rsyslog.d/50-default.conf /etc/rsyslog.d/50-default.conf.bak
	fi
	cp $PGPOOL_JOBS_PATH/conf/50-default.conf /etc/rsyslog.d/50-default.conf
	cp $PGPOOL_JOBS_PATH/conf/pgpool.logrotate /etc/logrotate.d/pgpool
	service rsyslog restart
}

function start_pgpool() {
	$PGPOOL_INSTALL_PATH/bin/pgpool -f $PGPOOL_JOBS_PATH/conf/pgpool.conf -F $PGPOOL_JOBS_PATH/conf/pcp.conf -n &
	sleep 5
}

function assign_pgnode_index() {
	echo "Assign pg node index to each node."
	local node_count=0
	local node_info=""
	set +e
	node_count=`$PGPOOL_INSTALL_PATH/bin/pcp_node_count -h $pcp_host -p $pcp_port -U $pcp_user -w`
	for (( i=0; i<$node_count; i++ ))
	do
		node_info=`$PGPOOL_INSTALL_PATH/bin/pcp_node_info -h $pcp_host -p $pcp_port -U $pcp_user -w $i`
		IFS=" " read -ra ARR <<< "$node_info"
		ssh ${db_user}@${ARR[0]} "touch $CLUSTER_PATH/pgnode_index && echo $i > $CLUSTER_PATH/pgnode_index || echo $i > $CLUSTER_PATH/pgnode_index"
	done
	set -e
}

case "$1" in
	'start')
		wait_ssh
		install
		config
		config_rsyslog
		start_pgpool
		assign_pgnode_index
	;;
	'stop')
		set +e
		$PGPOOL_INSTALL_PATH/bin/pgpool -f $PGPOOL_JOBS_PATH/conf/pgpool.conf -F $PGPOOL_JOBS_PATH/conf/pcp.conf -m fast stop
		sleep 5
	;;
esac