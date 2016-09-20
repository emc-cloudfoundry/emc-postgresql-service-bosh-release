#!/bin/bash
# Recovery script for streaming replication.
echo "Start recovery_1st_stage process of online recovery!"

/var/vcap/jobs/postgresql/bin/pg_debugger recovery_1st_stage /var/vcap/jobs/postgresql/bin/online_recovery.sh recovery_1st_stage $1 $2 $3 $4