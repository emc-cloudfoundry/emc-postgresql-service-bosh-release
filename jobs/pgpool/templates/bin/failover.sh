#!/bin/bash
# Failover command for streaming replication.
# failover.sh %d %h %D %H %R %P ----  value from pgpool.conf
# Special values:
                                   #   %d = Backend ID of a detached node.
                                   #   %h = Hostname of a detached node.
                                   #   %p = Port number of a detached node.
                                   #   %D = Database cluster directory of a detached node.
                                   #   %m = New master node ID.
                                   #   %H = Hostname of the new master node.
                                   #   %M = Old master node ID.
                                   #   %P = Old primary node ID.
                                   #   %r = new master port number
                                   #   %R = new master database cluster path
                                   #   %% = '%' character
set -x
db_user="<%= p('postgresql.super_user.name') %>"
trigger_file="<%= p('postgresql.trigger_file') %>"

failed_node_id=$1
failed_node_hostname=$2
failed_node_db_cluster_dir=$3
new_primary_hostname=$4
new_primary_db_cluster_dir=$5
old_primary_node_id=$6
if [ "${failed_node_id}" -eq "${old_primary_node_id}" ]; then
	ssh $db_user@$failed_node_hostname "rm -f $failed_node_db_cluster_dir/is_primary_node"
	ssh $db_user@$new_primary_hostname "touch $trigger_file"
	ssh $db_user@$new_primary_hostname "touch $new_primary_db_cluster_dir/is_primary_node"
	exit 0
fi