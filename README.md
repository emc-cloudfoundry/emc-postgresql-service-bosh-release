# emc-postgresql-service-bosh-release
This BOSH release should work with [emc-ssh-bosh-release].

`pgpool-II` version: 3.5.2

`postgreSQL` version: 9.5.1

## Features:
 - HA for PostgreSQL nodes - Multiple PostgreSQL nodes are supported and you can specify the HA mode by your deployment design. when you deploy multiple PostgreSQL nodes with "stream" HA mode, one of them is primary node, and others are standby nodes. When the primary node goes fail, a failover procedure is going to be performed automatically; one standby node will be picked up to become a new primary node. 
 - Synchronous Replications - When you set HA mode of multiple PostgreSQL nodes to the value "stream", you have a choice to make standby nodes replicate primary node synchronously.
 - Load Balance - The “SELECT” query will be distributed among available nodes to improve the system’s overall throughput.
 - Continuous archiving and Point-in-Time recovery - You can setup an archive host to accept the WAL segments from PostgreSQL server, then you can restore the database to any point of time.
## Restrictions
 - The HA mode only can be set to “stream”, which is a kind of hot primary/standby mode.
 - pgpool doesn't support HA.
 - Each postgreSQL node should be deployed to a dedicated host.
 - pgpool should be deployed on a dedicated host.
## Deployment
1. Targeting to your bosh director
    ```sh
    $ bosh target BOSH_DIRECTOR
    ```
2. Downloading the project
    ```sh
    $ git clone https://github.com/emc-cloudfoundry/emc-postgresql-service-bosh-release.git
    $ cd emc-postgresql-service-bosh-release
    ```
3. Creating PostgreSQL service bosh release:
    ```sh
    $ bosh create release --force
    $ bosh create release --force --final
    ```
4. Uploading the release.
    ```sh
    $ bosh uplaod release
    ```
5. Editing the deployment manifest. We have [a sample deployment manifest file](https://github.com/emc-cloudfoundry/emc-postgresql-service-bosh-release/blob/master/pg_multi_nodes.yml), you can simply edit it refer to your environment.

## Deployment Manifest
### Jobs Order
BOSH will run jobs in order of the sequence of "jobs" array in the deployment manifest, so please follow below sample to arrange your "jobs" array.
```yaml
jobs:
- name: archiving
  templates:
  - name: ssh
    release: <%= ssh_release_name %>
  ...
- name: postgresql
  templates:
  - name: ssh
    release: <%= ssh_release_name %>
  - name: postgresql
    release: <%= pg_release_name %>
  ...
- name: pgpool
  templates:
  - name: ssh
    release: <%= ssh_release_name %>
  - name: pgpool
    release: <%= pg_release_name %>
  ...
```
### Properties Section
`user_<index> `(map) - You can define any number of this element in properties section. The content of user_<index> element will be copied to other element where refers to this element.

`pgpool.hosts`(array) - The value type of this variable is array. You can only add one IP addresses (only can be IP address, DO NOT set to a hostname) for this variable because pgpool does not support HA. 

`pgpool.port`(integer) - The port number used by pgpool to listen for connections. Default is 9999.

`num_init_children`(integer) - The number of preforked pgpool server processes. Default is 32. num_init_children is also the concurrent connections limit to pgpool from clients.

`child_life_time`(integer) - A pgpool-II child process' life time in seconds. When a child is idle for that many seconds, it is terminated and a new child is created. This parameter is a measure to prevent memory leaks and other unexpected errors. Default value is 300 (5 minutes), 0 disables this feature. If this properties is absent in manifest, default value will be performed. Note that this doesn't apply for processes that have not accepted any connection yet.

`client_idle_limit`(integer) - Disconnect a client if it has been idle for client_idle_limit seconds after the last query has completed. This is useful to prevent pgpool childs from being occupied by a lazy client or a broken TCP/IP connection between client and pgpool. The default value for client_idle_limit is 500, 0 means the feature is turned off. If this properties is absent in manifest, default value will be performed. This parameter is ignored in the second stage of online recovery.

`child_max_connections`(integer) - A pgpool-II child process will be terminated after this many connections from clients.

`connection_life_time`(integer) - Cached connections expiration time in seconds. An expired cached connection will be disconnected. Default is 0, which means the cached connections will not be disconnected.

`pg_servers_load_balance`(boolean) - When set to true, SELECT queries will be distributed to each backend for load balancing. Default is true.

`stream_repl_delay_threshold`(integer) - This property is only valid when the property “postgresql.ha_mode” is set to `stream`. Specifies the maxium tolerated replication delay of the standby against the primary node in WAL bytes. If the delay exceeds stream_repl_delay_threshold, the SELECT queries will not be sent to the standby node anymore, until the standby has caught-up. If stream_repl_delay_threshold is 0, the delay checking is not performed. By default, this check is performed every 10 seconds.

`pgpool.pcp_user`(map) - This property can refer to one of user_<index> element. PCP is a control interface where an administrator can collect pgpool status, and terminate pgpool processes remotely. pcp_user is used for authentication by this interface.

`pgpool.pcp_port`(integer) - The port number where PCP process accepts connections. Default is 9898.

`pgpool.log.facility`(string) - By default, pgpool emits log message into syslog. This parameter determines the syslog "facility" to be used. You can choose from LOCAL0, LOCAL1, LOCAL2, LOCAL3, LOCAL4, LOCAL5, LOCAL6, LOCAL7; the default is LOCAL0.

`pgpool.log.size`(integer) - The unit of value is "Megabyte". Once the log file of pgpool reaches this size, it will be renamed to "pgpool.log.<index>", and a new log file "pgpool.log" will be created. The default is 100.

`pgpool.log.rotate`(integer) - The default is 5.

`postgresql.synchronous_replication`(boolean) - if the property is set into "true", PgSQL will set as stream based synchronous replication(http://www.postgresql.org/docs/9.5/static/warm-standby.html#SYNCHRONOUS-REPLICATION). The default is false.

`postgresql.max_connections`(integer) - Specifies the maximum number of concurrent connections to the database server. If the property is absent, it'll be set to default value "100".

`postgresql.shared_buffers`(string) - Specifies the amount of memory the database server uses for shared memory buffers. If the property is absent, it'll be set to default value "128MB", a reasonable starting value for this property  is 25% of the memory in your system.

`postgresql.max_wal_senders`(integer) - Specifies the maximum number of concurrent connections from standby servers or streaming base backup clients. This property shows how many standby servers you would like to deploy. Typically, subtracting 1 from the element number of “pg_hosts” equals the value.

`postgresql.hosts`(array) - You can add any number of host’s IP addresses (only can be IP address, DO NOT use hostname) in this variable value, and each of them will be deployed as a PostgreSQL node.

`postgresql.port`(integer) - The TCP port the PostgreSQL server listens on; 5432 by default.

`postgresql.super_user`(map) - Specifies a user who is used to create database cluster on every PostgreSQL server, so this user is the super user of every database.

`postgresql.trigger_file`(file) - Specifies a file path on PostgreSQL host, the file will be used in failover procedure.

`postgresql.host-based_auth`(array) - The elements in this array will be added into pg_hba.conf file on every postgresql node for the postgresql cluster.

`postgresql.log.file`(file) - The file name of postgresql server's log file. By default, logging collector is enabled for every postgresql server. 

`postgresql.log.rotation_age`(integer) - This parameter determines the maximum lifetime of an individual log file. After this many minutes have elapsed, a new log file will be created. Set to zero to disable time-based creation of new log files. Default is 1440.

`postgresql.log.rotation_size`(integer) - This parameter determines the maximum size of an individual log file. After this many kilobytes have been emitted into a log file, a new log file will be created. Set to zero to disable size-based creation of new log files. Default is 100000.

`postgresql.log.min_messages`(enum) - Controls which message levels are written to the server log. Valid values are DEBUG5, DEBUG4, DEBUG3, DEBUG2, DEBUG1, INFO, NOTICE, WARNING, ERROR, LOG, FATAL, and PANIC. Each level includes all the levels that follow it. The later the level, the fewer messages are sent to the log. The default is WARNING.

`postgresql.log.min_error_statement`(enum) - Controls which SQL statements that cause an error condition are recorded in the server log. The current SQL statement is included in the log entry for any message of the specified severity or higher. Valid values are DEBUG5, DEBUG4, DEBUG3, DEBUG2, DEBUG1, INFO, NOTICE, WARNING, ERROR, LOG, FATAL, and PANIC. The default is ERROR, which means statements causing errors, log messages, fatal errors, or panics will be logged.

`postgresql.log.line_prefix`(string) - This is a printf-style string that is output at the beginning of each log line.

`postgresql.archiving.archive_mode`(enum) - “on”: enable archive, completed WAL segments are sent to archive host. “off”: disable archive.

`postgresql.archiving.archive_timeout`(integer) - The archive process is only executed for completed WAL segments. Hence, if your PostgreSQL server generates little WAL traffic, there could be a long delay between the completion of a transaction and its safe recording in archive host. To limit how old unachieved data can be, you can set this property to force the PostgreSQL server to switch to a new WAL segment file periodically. By default, this property is set to “3600” seconds (one hour).

`postgresql.archiving.archive_host`(string) - The IP address of archive host.

`postgresql.archiving.archive_dir`(file) - This is a directory name on archive host, where the WAL segments will be stored. This directory will be created under “/var/vcap/store/” on archive host.

`postgresql.archiving.basebackup_cron`(string) - If you enable the archive process for a PostgreSQL deployment, the base backup procedure of database’s data directory would be a routine maintenance job on OS. With this property, you can set the schedule of this cron job.

`postgresql.archiving.basebackup_host`(string) - The IP address of base backup host.

`postgresql.archiving.basebackup_dir`(file) - This is a directory name on base backup host, where the backup of database data directory will be store. This directory will be created under “/var/vcap/store/” on base backup host.

`ssh`(map) - refer to [emc-ssh-bosh-release].

   [emc-ssh-bosh-release]: <https://github.com/emc-cloudfoundry/emc-ssh-bosh-release>