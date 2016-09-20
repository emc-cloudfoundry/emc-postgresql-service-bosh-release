#!/bin/bash
echo "Start restoring WAL files."
set -e
set -x
archive_host=<%= p("postgresql.archiving.archive_host") %>
archive_dir=<%= p("postgresql.archiving.archive_dir") %>
archive_path=/var/vcap/store/$archive_dir
archive_file=$1
dest_path=$2

archive_file_exists=`ssh $archive_host "test -f $archive_path/$archive_file" && echo true || echo false`

if [ "${archive_file_exists}" == "true" ]; then
	scp $archive_host:$archive_path/$archive_file  $dest_path 
	exit 0
else
	echo "The $archive_file does not exist in archive destination."
	exit 1
fi