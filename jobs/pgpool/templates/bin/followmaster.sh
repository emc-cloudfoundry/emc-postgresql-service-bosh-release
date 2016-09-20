#!/bin/bash
# /var/vcap/jobs/pgpool/bin/followmaster.sh %d %h %D
# Special values:
                                   #   %d = Backend ID of a detached node.
                                   #   %h = Hostname of a detached node.
                                   #   %p = Port number of a detached node.
                                   #   %D = Database cluster directory of a detached node.
                                   #   %m = new master node id
                                   #   %H = hostname of the new master node
                                   #   %M = old master node id
                                   #   %P = old primary node id
                                   #   %r = new master port number
                                   #   %R = new master database cluster path
                                   #   %% = '%' character

set -x
set -e
pg_version=<%= p("postgresql.version") %>
db_user="<%= p('postgresql.super_user.name') %>"
db_port="<%= p('postgresql.port') %>"
trigger_file="<%= p('postgresql.trigger_file') %>"
<% pgpool_hosts = p('pgpool.hosts') %>
pcp_host=<%= pgpool_hosts[index] %>
pcp_port=<%= p("pgpool.pcp_port") %>
pcp_user=<%= p("pgpool.pcp_user.name") %>

PG_INSTALL_PATH=/var/vcap/packages/postgresql/${pg_version}
PGPOOL_INSTALL_PATH=/var/vcap/packages/pgpool


detached_node_id=$1
detached_node_host=$2
detached_node_cluster_dir=$3


echo "start follow master."
is_running=`ssh ${detached_node_host} "test -f $detached_node_cluster_dir/postmaster.pid && echo 'true' || echo 'false'"`
if [ "${is_running}" == "true" ]; then
  echo "The pgsql server on detached node is running, so restart it to follow the new master."
  ssh $detached_node_host "/var/vcap/bosh/bin/monit restart postgresql"
else
  echo "The pgsql server on detached node is NOT running, maybe this node is the dead master node, so do nothing."
fi
