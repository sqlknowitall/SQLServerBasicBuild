SET NOCOUNT ON;

PRINT '/***********************************************************************************************/';
SELECT  @@SERVERNAME;

DECLARE @start_date DATETIME ,
    @end_date DATETIME;

SET @start_date = DATEADD(DAY, -1, GETDATE());
SET @end_date = GETDATE() + 1;

PRINT 'Report Dates ';
PRINT 'Start = ' + CONVERT(VARCHAR(20), @start_date, 100); 
PRINT 'End = ' + CONVERT(VARCHAR(20), @end_date, 100);

--FIND ACTIVE NODE
SELECT  'Active Node = '
        + CONVERT(VARCHAR(64), SERVERPROPERTY('ComputerNamePhysicalNetBIOS'));


--NODE NAMES
IF EXISTS(SELECT  *
FROM    ::
        fn_virtualservernodes())
BEGIN
PRINT('Cluster nodes below')
SELECT  *
FROM    ::
        fn_virtualservernodes();
END
ELSE PRINT('NOT CLUSTERED')


--CURRENT MEMORY USED
SELECT  'Total Memory Currently Used by SQL Server' ,
        committed_kb / 1024 AS 'MBs used'
FROM    sys.dm_os_sys_info;

--TARGET MEMORY
SELECT  'Total Memory SQL Server is willing to consume' ,
        committed_target_kb AS 'MBs used'
FROM    sys.dm_os_sys_info;

--TOTAL SERVER MEMORY
SELECT  'Total Memory on the Server is' ,
        CONVERT(INT, ( physical_memory_kb / 1024.0 )) AS 'Current (RAM)'
FROM    sys.dm_os_sys_info;


--UPDATE CURRENTLY CONFIGURED VALUE TO SHOW ADVANCED OPTIONS
EXEC sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO

--VERIFY CONFIGURED MEMORY
EXEC sp_configure 'max server memory (MB)';
GO

EXEC sp_configure 'min server memory (MB)';
GO

--VERIFY DATABASE STATUS
SELECT  'DATABASES NOT ONLINE' ,
        LTRIM(RTRIM(name)) ,
        LTRIM(RTRIM(state_desc))
FROM    master.sys.databases
WHERE   state_desc <> 'ONLINE';

--VERIFY KERBEROS
SET NOCOUNT ON

CREATE TABLE #xp (txtOut varchar(1024))

DECLARE @auth_scheme nvarchar(40), @auth_scheme2 nvarchar(40), @ServiceAccountName varchar(320), @cmd varchar(1024), @xp_check int

SELECT @auth_scheme = auth_scheme FROM sys.dm_exec_connections WHERE session_id = @@spid

IF @auth_scheme <> 'KERBEROS'
BEGIN
	SELECT @auth_scheme2 = @auth_scheme
	SELECT @auth_scheme = auth_scheme FROM sys.dm_exec_connections WHERE auth_scheme = 'KERBEROS'
	IF @auth_scheme <> 'KERBEROS'
	BEGIN
		SELECT 'No connections are currently using KERBEROS.'

		EXEC sys.xp_readerrorlog 0, 1, N'Service Principal Name'

		EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'SYSTEM\CurrentControlSet\Services\MSSQLSERVER', N'ObjectName', @ServiceAccountName OUTPUT, N'no_output'

		SELECT @cmd = 'SETSPN -l ' + @ServiceAccountName

		INSERT INTO #xp
		EXEC sys.xp_cmdshell @cmd

		SELECT txtOut AS [SETSPN -l AccountName]
		FROM #xp
		WHERE txtOut IS NOT NULL
	END
	ELSE
		SELECT 'KERBEROS is currently working, however you are currently authenticated using ' + @auth_scheme2 + ' authentication.'
END
ELSE
BEGIN
	SELECT 'You are currently authenticated using KERBEROS.'
END

DROP TABLE #xp

SET NOCOUNT OFF


--EXAMINE ERROR LOG
EXEC xp_readerrorlog 0, 1;
