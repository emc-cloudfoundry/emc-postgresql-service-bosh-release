#!/bin/bash
echo "Start archiving WAL files."
set -e
set -x
archive_host=<%= p("postgresql.archiving.archive_host") %>
archive_dir=<%= p("postgresql.archiving.archive_dir") %>
archive_path=/var/vcap/store/$archive_dir
archive_file=$1
dest_path=$2

archive_file_not_exists=`ssh $archive_host "test ! -f $archive_path/$archive_file" && echo true || echo false`

if [ "${archive_file_not_exists}" == "true" ]; then
	scp $dest_path $archive_host:$archive_path/$archive_file 
	exit 0
else
	echo "The $archive_file exists in archive destination."
	exit 0
fi