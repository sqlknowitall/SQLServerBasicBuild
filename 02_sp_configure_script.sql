/*
PURPOSE: Set several sp_configure options to begin building the server

USAGE:		Execute script as is
----------------------------------------------------------------------------------------------
REVISION HISTORY:
Date				Developer Name				Change Description                                    
----------			--------------				------------------
07/18/2018			Jared Karney				Original Version
08/12/2019			Jared Karney				Changed max and min memory to MS standards
----------------------------------------------------------------------------------------------
*/

--enable advanced options 
EXEC sp_configure 'advanced options', 1
RECONFIGURE WITH OVERRIDE
GO

--enable xp_cmdshell for build purposes. We will disable this later
EXEC sp_configure 'xp_cmdshell',1
reconfigure with override
GO

--turn on database mail
EXEC sp_configure 'database mail xps', 1
RECONFIGURE WITH OVERRIDE
GO

--turn on SQL Agent node
EXEC sp_configure 'agent xps', 1
RECONFIGURE WITH OVERRIDE
GO

--enable remote admin connections
EXEC sp_configure 'remote admin connections', 1
RECONFIGURE WITH OVERRIDE
GO

--set cost threshold for parallelism to something other than 5
EXEC sp_configure 'cost threshold for parallelism', 50;
RECONFIGURE WITH OVERRIDE
GO

--enable optimize for ad hoc workloads
EXEC sp_configure 'optimize for ad hoc workloads', 1
RECONFIGURE WITH OVERRIDE
GO

--enable backup compression
EXEC sp_configure 'backup compression', 1
RECONFIGURE WITH OVERRIDE
GO


--begin setting max and min memory
--change @execute to 0 if you only want recommendations
SET NOCOUNT ON;

-- declare local variables
DECLARE @InstanceName		SYSNAME
DECLARE @SQLVersionMajor	TINYINT
DECLARE @ServerMemory		INT
DECLARE @InstanceMinMemory	INT
DECLARE @InstanceMaxMemory	INT
DECLARE @SQL				NVARCHAR(MAX)
DECLARE @Execute			BIT
DECLARE @MaxWorkerThreads	INT
DECLARE @debug BIT

--create temp table for sp_configure results
CREATE TABLE #maxworkerthreads (name nvarchar(35), minimum int, maximum int, config_value int, run_value int)

--Set this in MB to determine a setting for a specific amount of RAM, elst it will be the connected machine
SET @ServerMemory = NULL

--change to 1 to set the values for the server
SET @Execute = 0

--for debugging
SET @debug = 0

-- initialize local variables
SELECT	@SQLVersionMajor	= @@MicrosoftVersion / 0x01000000, -- Get major version
		@InstanceName		= @@SERVERNAME  + ' (' + CAST(SERVERPROPERTY('productversion') AS VARCHAR) + ' - ' +  LOWER(SUBSTRING(@@VERSION, CHARINDEX('X',@@VERSION),4))  + ' - ' + CAST(SERVERPROPERTY('edition') AS VARCHAR)

-- get the server memory
-- wrap queries execution with sp_executesql to avoid compilation errors
IF @SQLVersionMajor >= 11 AND @ServerMemory IS NULL
BEGIN
	SET @SQL = 'SELECT @ServerMemory = physical_memory_kb/1024 FROM	sys.dm_os_sys_info'
	EXEC sp_executesql @SQL, N'@ServerMemory int OUTPUT', @ServerMemory = @ServerMemory OUTPUT
END
ELSE IF @SQLVersionMajor < 11
BEGIN
	PRINT 'SQL Server versions before 2005 are not supported by this script.'
	RETURN
END

-- fix rounding issues
SET @ServerMemory = @ServerMemory + 1

-- Get max worker threads 
INSERT INTO #maxworkerthreads
EXEC sp_configure 'max worker threads'

IF(SELECT run_value FROM #maxworkerthreads WHERE name = 'max worker threads') <> 0
BEGIN
SELECT @MaxWorkerThreads = run_value
FROM #maxworkerthreads
WHERE name = 'max worker threads'
END
ELSE
BEGIN
SELECT @MaxWorkerThreads = 512 + ((cpu_count - 4) * 16) 
FROM sys.dm_os_sys_info
END
DROP TABLE #maxworkerthreads

--for debugging
IF @debug = 1
BEGIN
PRINT '@serverMemory = ' + CAST(@serverMemory AS VARCHAR(25))
PRINT '@maxworkerthreads = ' + CAST(@maxworkerthreads AS VARCHAR(25))
END

-- now determine max server settings
-- used Microsoft's formula from https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/server-memory-server-configuration-options?view=sql-server-2017
-- reserve 1-4 GB of RAM for the OS, and then calculate required memory from thread stack needed (max num worker threads*2MB) + 256MB for reserved startup

SELECT	@InstanceMaxMemory = 	CASE	WHEN @ServerMemory <= 1024*2 THEN @ServerMemory - 512  -- @ServerMemory <= 2 GB
										WHEN @ServerMemory <= 1024*4 THEN @ServerMemory - 1024 -- @ServerMemory between 2 GB & 4 GB
										WHEN @ServerMemory <= 1024*8 THEN @ServerMemory - (2096+(@MaxWorkerThreads*2)+256) -- @ServerMemory between 4 GB & 8 GB
										ELSE @ServerMemory - (4096+(@MaxWorkerThreads*2)+256) -- @ServerMemory > 8GB
								END,
		@InstanceMinMemory =	CEILING(@InstanceMaxMemory * .75) -- set minimum memory to 75% of the maximum

-- adjust the server min / max memory settings accordingly
SET @SQL = 'EXEC sp_configure ''Show Advanced Options'', 1;	
RECONFIGURE WITH OVERRIDE; 
EXEC sp_configure ''min server memory'',' + CONVERT(VARCHAR(6), @InstanceMinMemory) +'; 
RECONFIGURE WITH OVERRIDE; 
EXEC sp_configure ''max server memory'',' + CONVERT(VARCHAR(6), @InstanceMaxMemory) +'; 
RECONFIGURE WITH OVERRIDE; 
--EXEC sp_configure ''Show Advanced Options'', 0; 
--RECONFIGURE WITH OVERRIDE;'

PRINT '----------------------------------------------------------------------'
PRINT 'Instance: ' + @InstanceName
PRINT '----------------------------------------------------------------------'
PRINT 'Determined Minimum Instance Memory: ' + CONVERT(VARCHAR(6), @InstanceMinMemory) + ' MB'
PRINT '----------------------------------------------------------------------'
PRINT 'Determined Maximum Instance Memory: ' + CONVERT(VARCHAR(6), @InstanceMaxMemory) + ' MB' 
PRINT '----------------------------------------------------------------------'

IF @Execute = 1
BEGIN
	
	PRINT 'Executed commands: ' + CHAR(13) + CHAR(13) + @SQL
	PRINT CHAR(13)
	PRINT '----------------------------------------------------------------------'
	PRINT CHAR(13)
	
	EXEC sp_executesql @SQL

	PRINT CHAR(13)
	PRINT '----------------------------------------------------------------------'

END
ELSE
BEGIN

	PRINT 'Commands to execute: ' + CHAR(13) + CHAR(13) + @SQL
	PRINT CHAR(13)
	PRINT '----------------------------------------------------------------------'

END

