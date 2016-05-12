sp_configure 'advanced options', 1
RECONFIGURE WITH OVERRIDE
GO
sp_configure 'xp_cmdshell',1
reconfigure with override
GO
sp_configure 'database mail xps', 1
RECONFIGURE WITH OVERRIDE
GO
sp_configure 'agent xps', 1
RECONFIGURE WITH OVERRIDE
GO
sp_configure 'remote admin connections', 1
RECONFIGURE WITH OVERRIDE
GO

sp_configure 'cost threshold for parallelism', 50;
RECONFIGURE WITH OVERRIDE
GO

sp_configure 'optimize for ad hoc workloads', 1
RECONFIGURE WITH OVERRIDE
GO

SET NOCOUNT ON;

-- declare local variables
DECLARE @InstanceName		SYSNAME
DECLARE @SQLVersionMajor	TINYINT
DECLARE @ServerMemory		INT
DECLARE @InstanceMinMemory	INT
DECLARE @InstanceMaxMemory	INT
DECLARE @SQL				NVARCHAR(MAX)
DECLARE @Execute			BIT

-- initialize local variables
SELECT	@SQLVersionMajor	= @@MicrosoftVersion / 0x01000000, -- Get major version
		@InstanceName		= @@SERVERNAME  + ' (' + CAST(SERVERPROPERTY('productversion') AS VARCHAR) + ' - ' +  LOWER(SUBSTRING(@@VERSION, CHARINDEX('X',@@VERSION),4))  + ' - ' + CAST(SERVERPROPERTY('edition') AS VARCHAR),
		@Execute			= 1

-- get the server memory
-- wrap queries execution with sp_executesql to avoid compilation errors
IF @SQLVersionMajor >= 11
BEGIN
	
	SET @SQL = 'SELECT @ServerMemory = physical_memory_kb/1024 FROM	sys.dm_os_sys_info'
	EXEC sp_executesql @SQL, N'@ServerMemory int OUTPUT', @ServerMemory = @ServerMemory OUTPUT

END
ELSE
IF @SQLVersionMajor in (9, 10)
BEGIN
	
	SET @SQL = 'SELECT	@ServerMemory = physical_memory_in_bytes/1024/1024 FROM	sys.dm_os_sys_info'
	EXEC sp_executesql @SQL, N'@ServerMemory int OUTPUT', @ServerMemory = @ServerMemory OUTPUT

END
ELSE
BEGIN
	
	PRINT 'SQL Server versions before 2005 are not supported by this script.'
	RETURN

END

-- fix rounding issues
SET @ServerMemory = @ServerMemory + 1

-- now determine max server settings
-- utilized formula from Jonathan Kehayias: https://www.sqlskills.com/blogs/jonathan/how-much-memory-does-my-sql-server-actually-need/
-- reserve 1 GB of RAM for the OS, 1 GB for each 4 GB of RAM installed from 4–16 GB and then 1 GB for every 8 GB RAM installed above 16 GB RAM.

SELECT	@InstanceMaxMemory = 	CASE	WHEN @ServerMemory <= 1024*2 THEN @ServerMemory - 512  -- @ServerMemory < 2 GB
										WHEN @ServerMemory <= 1024*4 THEN @ServerMemory - 1024 -- @ServerMemory between 2 GB & 4 GB
										WHEN @ServerMemory <= 1024*16 THEN @ServerMemory - 1024 - CEILING((@ServerMemory-4096) / (4.0*1024))*1024 -- @ServerMemory between 4 GB & 8 GB
										WHEN @ServerMemory > 1024*16 THEN @ServerMemory - 4096 - CEILING((@ServerMemory-1024*16) / (8.0*1024))*1024 -- @ServerMemory > 8 GB
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

