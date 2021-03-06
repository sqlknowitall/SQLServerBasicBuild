/* 
   This will recommend a MAXDOP setting appropriate for your machine's NUMA memory
   configuration.  You will need to evaluate this setting in a non-production 
   environment before moving it to production.
   Recommendations from https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/configure-the-max-degree-of-parallelism-server-configuration-option?view=sql-server-2017#Guidelines

   MAXDOP can be configured using:  
   EXEC sp_configure 'max degree of parallelism',X;
   RECONFIGURE

   If this instance is hosting a Sharepoint database, you MUST specify MAXDOP=1 
   (URL wrapped for readability)
   http://blogs.msdn.com/b/rcormier/archive/2012/10/25/
   you-shall-configure-your-maxdop-when-using-sharepoint-2013.aspx

   Biztalk (all versions, including 2010): 
   MAXDOP = 1 is only required on the BizTalk Message Box
   database server(s), and must not be changed; all other servers hosting other 
   BizTalk Server databases may return this value to 0 if set.
   http://support.microsoft.com/kb/899000
*/

DECLARE @majorVersion INT;
DECLARE @CoreCount int;
DECLARE @NumaNodes int;
DECLARE @MaxDOP int;

SELECT @majorVersion = CAST(SERVERPROPERTY('ProductMajorVersion') AS INT);

SET @CoreCount = (SELECT i.cpu_count from sys.dm_os_sys_info i);
SET @NumaNodes = (
    SELECT MAX(c.memory_node_id) + 1 
    FROM sys.dm_os_memory_clerks c 
    WHERE memory_node_id < 64
    );

IF @majorVersion IS NULL OR @majorVersion < 14 --before SQL 2016
BEGIN
	IF @CoreCount >= 4
	BEGIN

		--@CoreCount / @NumaNodes
		SET @MaxDOP = @CoreCount / @NumaNodes; 

		/* Cap MAXDOP at 8, according to Microsoft */
		IF @MaxDOP > 8 SET @MaxDOP = 8;

		PRINT 'Suggested MAXDOP = ' + CAST(@MaxDOP as varchar(max));
	END
	ELSE
	BEGIN
		PRINT 'Suggested MAXDOP = 0 since you have less than 4 cores total.';
		PRINT 'This is the default setting, you likely do not need to do';
		PRINT 'anything.';
	END
END
ELSE -- SQL 2016 or later
BEGIN
	IF @CoreCount >= 4
	BEGIN

		--@CoreCount / @NumaNodes
		SET @MaxDOP = @CoreCount / @NumaNodes; 

		/* Cap MAXDOP at 8, according to Microsoft */
		IF @MaxDOP > 16 SET @MaxDOP = @CoreCount/2;

		PRINT 'Suggested MAXDOP = ' + CAST(@MaxDOP as varchar(max));
	END
	ELSE
	BEGIN
		PRINT 'Suggested MAXDOP = 0 since you have less than 4 cores total.';
		PRINT 'This is the default setting, you likely do not need to do';
		PRINT 'anything.';
	END
END