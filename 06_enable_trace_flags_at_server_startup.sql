USE master
GO

IF EXISTS(SELECT 1 FROM sys.procedures WHERE name = 'uspSetServerTraceFlags')
DROP PROCEDURE uspSetServerTraceFlags;
GO

CREATE PROCEDURE [dbo].[uspSetServerTraceFlags]
----------------------------------------------------------------------------------
--																				--
-- Name: 		uspSetServerTraceFlags.sql										--
-- Developer:	Andreas Zimmermann												--
-- Date:		12/09/2013														--
-- Parameters:	N/A																--
-- Purpose:		Set global trace flags to run upon SQL Server startup.			--
--																				--
-- Annotations: Need to execute sp_procoption to enable this SP to auto 		--
--				execute whenever SQL Server instance starts: 					--
--				EXEC sp_procoption 'EnableTraceFlags', 'startup', 'true'		--
--																				--
-- Credits:		PASS Summit 2011 presentation by Victor Isakov:					--
--				Important Trace Flags That Every DBA_Rep Should Know				--
--																				--
--				SQL Server Books Online (BOL):									--
--				http://technet.microsoft.com/en-us/library/ms188396.aspx		--
--																				--
-- Changes:		N/A																-- 
--																				--
----------------------------------------------------------------------------------
AS
BEGIN
	------------------------------------------------------------------------------
	--  MAKE SURE YOU UNDERSTAND WHAT A TRACE FLAG DOES BEFORE IMPLEMENTATION!	--
	------------------------------------------------------------------------------
	-- Determine SQL Server Version / Edition (since some flags are version / edition dependent)
	DECLARE	 @ProductEdition NVARCHAR(50),
			 @ProductVersion NVARCHAR(50),
			 @Major		  INT,
			 @Minor		  INT,
			 @Build		  INT,
			 @Revision	  INT
	
	select	@ProductEdition = RTRIM(LTRIM(CONVERT(NVARCHAR(50), SERVERPROPERTY('Edition')))),
			@ProductVersion = RTRIM(LTRIM(CONVERT(NVARCHAR(50), SERVERPROPERTY('ProductVersion'))))

	select @Major		= 0
	select @Minor		= CHARINDEX('.', @ProductVersion, @Major + 1)
	select @Build		= CHARINDEX('.', @ProductVersion, @Minor + 1)
	select @Revision	= CHARINDEX('.', @ProductVersion, @Build + 1)

	select @Major		= CAST(SUBSTRING(@ProductVersion,@Major,@Minor) as int)
	select @Minor		= CAST(SUBSTRING(@ProductVersion,@Minor+1,@Build - @Minor - 1) as int)
	select @Build		= case	when @Revision > 0 then CAST(SUBSTRING(@ProductVersion,@Build+1,@Revision - @Build - 1) as int) 
								else CAST(SUBSTRING(@ProductVersion,@Build+1,LEN(@ProductVersion) - @Build) as int) end
	select @Revision	= case	when @Revision > 0 then CAST(SUBSTRING(@ProductVersion,@Revision+1,LEN(@ProductVersion) - @Revision) as int) 
								else 0 end

	-- Production Flags
	--DBCC TRACEON (610, -1); 	-- Controls minimally logged inserts into indexed tables (Data Loading Performance Guide / http://msdn.microsoft.com/en-us/library/dd425070%28v=sql.100%29.aspx)
	
	--IF		((@Major =   9) AND (@Minor = 0) AND (@Revision >= 4226)) -- Cumulative Update 4 for SQL Server 2005 Service Pack 3
	--	OR	((@Major =  10) AND (@Minor = 0) AND (@Revision >= 2714)) -- Cumulative Update 2 for SQL Server 2008 Service Pack 1
	--BEGIN
	--	DBCC TRACEON (834, -1); 	-- Allows SQL Server 2005 / 2008 to use large page allocations for the memory that is allocated for the buffer pool (KB920093 / http://support.microsoft.com/kb/920093). 
	--END

	--IF @ProductEdition = 'Standard Edition'
	--BEGIN
	--	DBCC TRACEON (835, -1); 	-- Enables “Lock Pages in Memory” support for SQL Server Standard Edition (KB970070 / http://support.microsoft.com/kb/970070, Memory Architecture http://msdn.microsoft.com/en-us/library/ms187499.aspx)
	--END

	DBCC TRACEON (1118, -1);	-- Directs SQL Server to allocate full (instead of mixed) extents to each tempdb object (KB328551 / http://support.microsoft.com/kb/328551, KB936185 / http://support.microsoft.com/kb/936185, Working with tempdb in SQL Server 2005 / http://technet.microsoft.com/library/Cc966545)
	
	--DBCC TRACEON (1204, -1); 	-- Writes information about deadlocks to the ERRORLOG in a “text format” (BOL).
	
	--DBCC TRACEON (1211, -1); 	-- Disables lock escalation based on memory pressure or number of locks (BOL).
	
	DBCC TRACEON (1222, -1); -- Write deadlocks to errorlog (BOL).
	
	--DBCC TRACEON (1224, -1); 	-- Disables lock escalation based on the number of locks (BOL).
	
	--DBCC TRACEON (2528, -1); 	-- Disables parallel checking of objects during DBCC CHECKDB, DBCC CHECKFILEGROUP and DBCC CHECKTABLE (BOL).
	
	DBCC TRACEON (3226, -1); -- Prevents successful backup operations from being logged (BOL).
	
	IF	(		((@Major =  9) AND (@Minor = 0) AND (@Build >= 4266))	-- Cumulative Update 6 for SQL Server 2005 Service Pack 3
			OR	((@Major = 10) AND (@Minor = 0) AND (@Build >= 2766))	-- Cumulative Update 7 for SQL Server 2008 Service Pack 1
			OR	((@Major = 10) AND (@Minor = 50))						-- SQL Server 2008 R2
			OR	((@Major = 11))											-- SQL Server 2012
			OR	((@Major = 12))											-- SQL Server 2014
		)
	BEGIN
		DBCC TRACEON (4199, -1); -- Enables all the fixes that were previously made for the query processor under many trace flags (KB974006 / http://support.microsoft.com/kb/974006)
	END

	-- DEV / UAT Flags
	--DBCC TRACEON (806, -1); 	-- Enables DBCC audit checks to be performed on pages to test for logical consistency problems (KB841776, http://support.microsoft.com/kb/841776 / SQL Server I/O Basics, http://technet.microsoft.com/en-au/library/cc917726.aspx).
	--DBCC TRACEON (818, -1); 	-- Enables an in-memory ring buffer that is used for tracking the last 2,048 successful write operations that are performed by the computer running SQL Server, not including sort and workfile I/Os (KB826433, http://support.microsoft.com/kb/826433).
	--DBCC TRACEON (3422, -1); 	-- Enables log record auditing (SQL Server I/O Basics, http://technet.microsoft.com/en-au/library/cc917726.aspx).
	--DBCC TRACEON (1200, -1); 	-- Returns locking information in real-time as your query executes
	--DBCC TRACEON (1806, -1); 	-- Explicitly disables instant file initialization (SQL Server I/O Basics, http://technet.microsoft.com/en-au/library/cc917726.aspx).
	--DBCC TRACEON (3004, -1); 	-- Returns more information about instant file initialization
	--DBCC TRACEON (3014, -1); 	-- Returns more information to the ERRORLOG about BACKUP
	--DBCC TRACEON (3502, -1); 	-- Writes information about CHECKPOINTs to the ERRORLOG
	--DBCC TRACEON (3505, -1); 	-- Disables automatic checkpoints (KB815436 / http://support.microsoft.com/kb/815436). 
END
GO

---

USE [master]
GO

IF EXISTS(SELECT 1 FROM sys.procedures WHERE name = 'uspEnableTraceFlags')
DROP PROCEDURE uspEnableTraceFlags;
GO

CREATE PROCEDURE [dbo].[uspEnableTraceFlags]
------------------------------------------------------------------------------
--														  					--
-- Name: 		uspEnableTraceFlags.sql										--
-- Developer:	Andreas Zimmermann											--
-- Date:		12/09/2013													--
-- Parameters:	N/A															--
-- Purpose:	Call uspSetServerTraceFlags to enable trace flags at	  		--	 
--			instance startup.	 											--
-- Changes:	N/A																-- 
--																			--
------------------------------------------------------------------------------
AS
BEGIN

	SET NOCOUNT ON
	
	EXECUTE master.[dbo].[uspSetServerTraceFlags]

END
GO

EXEC sp_procoption N'[dbo].[uspEnableTraceFlags]', 'startup', '1'
GO

EXECUTE [master].[dbo].[uspEnableTraceFlags]
GO