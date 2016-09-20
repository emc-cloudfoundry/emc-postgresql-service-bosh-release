#!/bin/bash
# Execute command by failback.
# failback.sh %h %R  ----  value from pgpool.conf
# Special values:
                                   #   %d = Backend ID of an attached node.
                                   #   %h = Hostname of an attached node.
                                   #   %p = Port number of an attached node.
                                   #   %D = Database cluster directory of an attached node.
                                   #   %m = new master node id
                                   #   %H = hostname of the new master node
                                   #   %M = old master node id
                                   #   %P = old primary node id
                                   #   %r = new master port number
                                   #   %R = new master database cluster path
                                   #   %% = '%' character
set -x

db_user="<%= p('postgresql.super_user.name') %>"
trigger_file="<%= p('postgresql.trigger_file') %>"

attached_node_host=$1
attached_node_cluster_dir=$2

echo "If the attached node was a primary node when it's down, try to delete the flag file is_primary_node"
ssh $db_user@$attached_node_host "rm -f $attached_node_cluster_dir/is_primary_node"

exit 0