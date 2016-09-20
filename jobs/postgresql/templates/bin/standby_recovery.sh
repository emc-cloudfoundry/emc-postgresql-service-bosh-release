#! /bin/bash
# Recovery script for streaming replication.
# This script is put on slave node for recovery.
set -x
set -e
db_user="<%= p('postgresql.super_user.name') %>"
db_password="<%= p('postgresql.super_user.password') %>"
port="<%= p('postgresql.port') %>"

trigger_file="<%= p('postgresql.trigger_file') %>"

destdir=$1
primaryhost=$2
standbyhost=$3

if [ ! -d $destdir/pg_xlog ]; then
	mkdir $destdir/pg_xlog
fi
chmod 700 $destdir/pg_xlog
if [ -f $destdir/recovery.done ]; then
	rm $destdir/recovery.done
fi
if [ -f $destdir/is_primary_node ]; then
	rm $destdir/is_primary_node
fi
if [ -f $destdir/recovery.conf ]; then 
	rm $destdir/recovery.conf
fi
cat > $destdir/recovery.conf <<EOF
standby_mode          = 'on'
primary_conninfo      = 'host=$primaryhost port=$port user=$db_user password=$db_password application_name=$standbyhost'
trigger_file          = '$trigger_file'
EOF