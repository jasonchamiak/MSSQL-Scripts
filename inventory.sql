--GET SQL Server Version--
SELECT SERVERPROPERTY('productversion') AS Version, SERVERPROPERTY ('productlevel') AS [Service Pack], SERVERPROPERTY ('edition') AS Edition
GO



--Database Count--
SELECT count(*) AS [Database Count] FROM master.sys.databases WHERE database_id > 4



--Clustered?--
DECLARE @i smallint
DECLARE @sql nvarchar(256)

SET @i = CONVERT(smallint, (SELECT SERVERPROPERTY('IsClustered')))

IF @i = 0
BEGIN
	SELECT 'No' AS [Clustered]
END
ELSE
	SET @sql = 'SELECT ''Yes'' AS [Clustered?], NodeName, status_description, is_current_owner FROM master.sys.dm_os_cluster_nodes'
	EXEC sp_executesql @sql
GO



--Log Shipping?
DECLARE @i tinyint
DECLARE @i_primary smallint
DECLARE @i_secondary smallint
DECLARE @sql nvarchar(256)

SET @i = 0
SET @i_primary = CONVERT(smallint, (SELECT count(*) FROM msdb.dbo.log_shipping_primary_databases))
SET @i_secondary = CONVERT(smallint, (SELECT count(*) FROM msdb.dbo.log_shipping_monitor_secondary))

IF @i_primary > 0
BEGIN
	SET @i = 1
END

IF @i_secondary > 0
BEGIN
	SET @i = @i + 2
END

IF @i = 1 OR @i = 3
BEGIN
	SELECT 'Primary' AS [Log_Shipping_Role]
		, lsmp.primary_server 
		, lspd.primary_database
        , lsps.secondary_server
		, lsps.secondary_database
	FROM msdb.dbo.log_shipping_primary_databases AS lspd
	JOIN msdb.dbo.log_shipping_primary_secondaries AS lsps ON lspd.primary_id = lsps.primary_id
	JOIN msdb.dbo.log_shipping_monitor_primary AS lsmp ON lspd.primary_id = lsmp.primary_id
END
ELSE IF @i = 2 OR @i = 3
BEGIN
	SELECT 'Secondary' AS [Log_Shipping_Role]
		, [secondary_server]
		, [secondary_database]
		, [primary_server]
		, [primary_database]
	FROM [msdb].[dbo].[log_shipping_monitor_secondary]
END
ELSE
SELECT 'No' AS [Log_Shipping]
GO



--Replication Publications?
DECLARE @i smallint

SET @i = CONVERT(smallint, (SELECT count(*) FROM master.sys.databases WHERE is_published = 1))

IF @i = 0
BEGIN
	SELECT 'No' AS [Repl_Publications]
END
ELSE
	SELECT 'Yes' AS [Repl_Publications], name AS [database] FROM master.sys.databases WHERE is_published = 1
GO



--Replication Subscriptions?
DECLARE @id smallint
DECLARE @maxId smallint
DECLARE @dbname sysname
DECLARE @sql nvarchar(512)

SET @id = 5
SET @maxId = (SELECT max(database_id) FROM sys.databases)

CREATE TABLE #SubscriberDbListing (subscriber_db sysname)
CREATE TABLE #SubscriptionListing (subscriber_db sysname, publisher sysname, publisher_db sysname, publication sysname) 

WHILE (@id <= @maxId)
BEGIN
	SET @dbname = (SELECT DB_NAME(database_id) FROM sys.databases WHERE database_id = @id  AND state = 0)
	SET @sql = 'IF EXISTS(SELECT name from [' + @dbname + '].[sys].[tables] WHERE name = ''MSreplication_subscriptions'') 
		SELECT ''' + @dbname + ''' AS [subscriber_db], [publisher], [publisher_db], [publication] FROM [' + @dbname + '].[dbo].[MSreplication_subscriptions]'

	INSERT INTO #SubscriptionListing
	EXEC sp_executesql @sql
	SET @id = @id + 1
END

SELECT 'Yes' AS [Repl_Subscriptions], subscriber_db, publisher, publisher_db, publication FROM #SubscriptionListing

DROP TABLE #SubscriberDbListing
DROP TABLE #SubscriptionListing
GO



--Database Mirroring?
DECLARE @i smallint

SET @i = CONVERT(smallint, (SELECT count(*) FROM master.sys.database_mirroring WHERE mirroring_guid IS NOT NULL))

IF @i = 0
BEGIN
	SELECT 'No' AS [DB_Mirroring]
END
ELSE
	SELECT 'Yes' AS [DB_Mirroring?], DB_NAME(database_id) AS [database]
		, mirroring_role_desc
		, mirroring_state_desc
		, mirroring_partner_name
		, mirroring_witness_name
		, mirroring_witness_state_desc 
	FROM master.sys.database_mirroring
	WHERE mirroring_guid IS NOT NULL
GO



--Availability Groups?--
DECLARE @i_enabled smallint
DECLARE @i_status smallint

SET @i_enabled = CONVERT(smallint, (SELECT SERVERPROPERTY('IsHadrEnabled')))
SET @i_status = CONVERT(smallint, (SELECT SERVERPROPERTY('HadrManagerStatus')))

IF (CONVERT(nvarchar(10), SERVERPROPERTY('productversion')) LIKE '11.%' OR CONVERT(nvarchar(10), SERVERPROPERTY('productversion')) LIKE '12.%') AND CONVERT(nvarchar(50), SERVERPROPERTY ('edition')) LIKE 'Enterprise%'
BEGIN
	IF @i_enabled = 1
	BEGIN
		SELECT 'Yes' AS [Avalailabilty_Groups], ag.name AS [Availability_Group_Name], hags.primary_replica, ar.replica_server_name AS [replica_servers]
		FROM master.sys.availability_groups AS ag
		JOIN master.sys.availability_replicas AS ar ON ag.group_id = ar.group_id
		JOIN master.sys.dm_hadr_availability_group_states AS hags ON ag.group_id = hags.group_id
		WHERE hags.primary_replica <> ar.replica_server_name

		SELECT adc.database_name AS [Availability_Group_Databases], ag.name AS [Availability_Group_Name], hags.primary_replica
		FROM master.sys.availability_databases_cluster AS adc
		JOIN master.sys.availability_groups AS ag ON adc.group_id = ag.group_id
		JOIN master.sys.dm_hadr_availability_group_states AS hags ON adc.group_id = hags.group_id
	END
	ELSE
		SELECT 'No' AS [Availability Groups]
END
ELSE
	SELECT 'No' AS [Availability Groups]
GO
