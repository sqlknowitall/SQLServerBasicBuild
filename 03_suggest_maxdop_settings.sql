/* 

	This will recommend a MAXDOP setting appropriate for your machine's NUMA memory
	configuration.
	https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/configure-the-max-degree-of-parallelism-server-configuration-option?view=sql-server-2017
	You should evaluate this setting in a non-production 
	environment before moving it to production.

	MAXDOP can be configured using:  
	EXEC sp_configure 'max degree of parallelism',X;
	RECONFIGURE wITH OVERRIDE

	If this instance is hosting a Sharepoint database, you MUST specify MAXDOP=1 
	http://blogs.msdn.com/b/rcormier/archive/2012/10/25/you-shall-configure-your-maxdop-when-using-sharepoint-2013.aspx

	Biztalk (all versions, including 2010):
	MAXDOP = 1 is only required on the BizTalk Message Box
	database server(s), and must not be changed; all other servers hosting other 
	BizTalk Server databases may return this value to 0 if set.
	http://support.microsoft.com/kb/899000
*/

DECLARE @CoreCount INT;
DECLARE @NumaNodes INT;
DECLARE @SQLVersionMajor TINYINT;
DECLARE @MaxDOP INT;

SET @CoreCount = (SELECT i.cpu_count FROM sys.dm_os_sys_info i);

SET @NumaNodes = (
    SELECT MAX(c.memory_node_id) + 1 
    FROM sys.dm_os_memory_clerks c 
    WHERE memory_node_id <> 64
    );

SELECT	@SQLVersionMajor = @@MicrosoftVersion / 0x01000000 --get major version

IF @SQLVersionMajor <= 12 --version is 2014 or earlier
BEGIN
	IF @NumaNodes = 1
	BEGIN
		IF @CoreCount <= 8
		BEGIN
			SET @MaxDOP = @CoreCount
		END
		ELSE
		BEGIN
			SET @MaxDOP = 8
		END
	END
	ELSE
	BEGIN
		IF @CoreCount/@NumaNodes <= 8
		BEGIN
			SET @MaxDOP = @CoreCount/@NumaNodes
		END
		ELSE
		BEGIN
			SET @MaxDOP = 8
		END
	END
END
ELSE
BEGIN
	IF @NumaNodes = 1
	BEGIN
		IF @CoreCount <= 8
		BEGIN
			SET @MaxDOP = @CoreCount
		END
		ELSE
		BEGIN
			SET @MaxDOP = 8
		END
	END
	ELSE
	BEGIN
		IF @CoreCount/@NumaNodes <= 16
		BEGIN
			SET @MaxDOP = @CoreCount/@NumaNodes
		END
		ELSE
		BEGIN
			SET @MaxDOP =
			CASE
				WHEN @CoreCount/@NumaNodes/2 > 16 THEN 16
				ELSE @CoreCount/@NumaNodes 
			END
		END
	END
END
		
PRINT 'Suggested MAXDOP = ' + CAST(@MaxDOP as varchar(max));

