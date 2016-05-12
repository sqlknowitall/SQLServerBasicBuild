-- 1. Verify the installed version
	SELECT  @@VERSION;
	GO

-- 2. sp_configure options 
	sp_configure 'advanced options', 1; 
	RECONFIGURE WITH OVERRIDE;
	GO
	sp_configure 'xp_cmdshell', 1; 
	RECONFIGURE WITH OVERRIDE;
	GO
	sp_configure 'database mail xps', 1; 
	RECONFIGURE WITH OVERRIDE;
	GO
	sp_configure 'agent xps', 1; 
	RECONFIGURE WITH OVERRIDE;
	GO
	sp_configure 'remote admin connections', 1; 
	RECONFIGURE WITH OVERRIDE;
	GO

	sp_configure 'cost threshold for parallelism', 50;
	RECONFIGURE WITH OVERRIDE;
	GO

	sp_configure 'optimize for ad hoc workloads', 1; 
	RECONFIGURE WITH OVERRIDE;
	GO

	SET NOCOUNT ON;

	-- declare local variables
	DECLARE @InstanceName SYSNAME;
	DECLARE @SQLVersionMajor TINYINT;
	DECLARE @ServerMemory INT;
	DECLARE @InstanceMinMemory INT;
	DECLARE @InstanceMaxMemory INT;
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Execute BIT;

	-- initialize local variables
	SELECT  @SQLVersionMajor = @@MicrosoftVersion / 0x01000000 , -- Get major version
			@InstanceName = @@SERVERNAME + ' ('
			+ CAST(SERVERPROPERTY('productversion') AS VARCHAR) + ' - '
			+ LOWER(SUBSTRING(@@VERSION, CHARINDEX('X', @@VERSION), 4)) + ' - '
			+ CAST(SERVERPROPERTY('edition') AS VARCHAR) ,
			@Execute = 1;

	-- get the server memory
	-- wrap queries execution with sp_executesql to avoid compilation errors
	IF @SQLVersionMajor >= 11
		BEGIN
	
			SET @SQL = 'SELECT @ServerMemory = physical_memory_kb/1024 FROM	sys.dm_os_sys_info';
			EXEC sp_executesql @SQL, N'@ServerMemory int OUTPUT',
				@ServerMemory = @ServerMemory OUTPUT;

		END;
	ELSE
		IF @SQLVersionMajor IN ( 9, 10 )
			BEGIN
	
				SET @SQL = 'SELECT	@ServerMemory = physical_memory_in_bytes/1024/1024 FROM	sys.dm_os_sys_info';
				EXEC sp_executesql @SQL, N'@ServerMemory int OUTPUT',
					@ServerMemory = @ServerMemory OUTPUT;

			END;
		ELSE
			BEGIN
	
				PRINT 'SQL Server versions before 2005 are not supported by this script.';
				RETURN;

			END;

	-- fix rounding issues
	SET @ServerMemory = @ServerMemory + 1;

	-- now determine max server settings
	-- utilized formula from Jonathan Kehayias: https://www.sqlskills.com/blogs/jonathan/how-much-memory-does-my-sql-server-actually-need/
	-- reserve 1 GB of RAM for the OS, 1 GB for each 4 GB of RAM installed from 4–16 GB and then 1 GB for every 8 GB RAM installed above 16 GB RAM.

	SELECT  @InstanceMaxMemory = CASE WHEN @ServerMemory <= 1024 * 2
									  THEN @ServerMemory - 512  -- @ServerMemory < 2 GB
									  WHEN @ServerMemory <= 1024 * 4
									  THEN @ServerMemory - 1024 -- @ServerMemory between 2 GB & 4 GB
									  WHEN @ServerMemory <= 1024 * 16
									  THEN @ServerMemory - 1024
										   - CEILING(( @ServerMemory - 4096 )
													 / ( 4.0 * 1024 )) * 1024 -- @ServerMemory between 4 GB & 8 GB
									  WHEN @ServerMemory > 1024 * 16
									  THEN @ServerMemory - 4096
										   - CEILING(( @ServerMemory - 1024 * 16 )
													 / ( 8.0 * 1024 )) * 1024 -- @ServerMemory > 8 GB
								 END ,
			@InstanceMinMemory = CEILING(@InstanceMaxMemory * .75);
	 -- set minimum memory to 75% of the maximum

	-- adjust the server min / max memory settings accordingly
	SET @SQL = 'EXEC sp_configure ''Show Advanced Options'', 1;	
	RECONFIGURE WITH OVERRIDE; 
	EXEC sp_configure ''min server memory'','
		+ CONVERT(VARCHAR(6), @InstanceMinMemory) + '; 
	RECONFIGURE WITH OVERRIDE; 
	EXEC sp_configure ''max server memory'','
		+ CONVERT(VARCHAR(6), @InstanceMaxMemory) + '; 
	RECONFIGURE WITH OVERRIDE; 
	--EXEC sp_configure ''Show Advanced Options'', 0; 
	--RECONFIGURE WITH OVERRIDE;';

	PRINT '----------------------------------------------------------------------';
	PRINT 'Instance: ' + @InstanceName;
	PRINT '----------------------------------------------------------------------';
	PRINT 'Determined Minimum Instance Memory: '
		+ CONVERT(VARCHAR(6), @InstanceMinMemory) + ' MB';
	PRINT '----------------------------------------------------------------------';
	PRINT 'Determined Maximum Instance Memory: '
		+ CONVERT(VARCHAR(6), @InstanceMaxMemory) + ' MB'; 
	PRINT '----------------------------------------------------------------------';

	IF @Execute = 1
		BEGIN
	
			PRINT 'Executed commands: ' + CHAR(13) + CHAR(13) + @SQL;
			PRINT CHAR(13);
			PRINT '----------------------------------------------------------------------';
			PRINT CHAR(13);
	
			EXEC sp_executesql @SQL;

			PRINT CHAR(13);
			PRINT '----------------------------------------------------------------------';

		END;
	ELSE
		BEGIN

			PRINT 'Commands to execute: ' + CHAR(13) + CHAR(13) + @SQL;
			PRINT CHAR(13);
			PRINT '----------------------------------------------------------------------';

		END;

-- 3. Suggest MAXDOP settings
	/* 
	   This will recommend a MAXDOP setting appropriate for your machine's NUMA memory
	   configuration.  You will need to evaluate this setting in a non-production 
	   environment before moving it to production.

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


	DECLARE @CoreCount INT;
	DECLARE @NumaNodes INT;

	SET @CoreCount = ( SELECT   i.cpu_count
					   FROM     sys.dm_os_sys_info i
					 );
	SET @NumaNodes = ( SELECT   MAX(c.memory_node_id) + 1
					   FROM     sys.dm_os_memory_clerks c
					   WHERE    memory_node_id < 64
					 );

	IF @CoreCount > 4 /* If less than 5 cores, don't bother. */
		BEGIN
			DECLARE @MaxDOP INT;

		--@CoreCount / @NumaNodes
			SET @MaxDOP = @CoreCount / @NumaNodes; 


		/* Cap MAXDOP at 8, according to Microsoft */
			IF @MaxDOP > 8
				SET @MaxDOP = 8;

			PRINT 'Suggested MAXDOP = ' + CAST(@MaxDOP AS VARCHAR(MAX));
		END;
	ELSE
		BEGIN
			PRINT 'Suggested MAXDOP = 0 since you have less than 4 cores total.';
			PRINT 'This is the default setting, you likely do not need to do';
			PRINT 'anything.';
		END;

-- 4. Enable backup compression as default
	-- enable backup compression by default
	-- 2008: EE
	-- 2008 R2 and newer: SE & up

	-- Determine SQL Server Version / Edition
	DECLARE @ProductEdition NVARCHAR(50) ,
		@ProductVersion NVARCHAR(50) ,
		@Major INT ,
		@Minor INT ,
		@Build INT ,
		@Revision INT;

	SELECT  @ProductEdition = RTRIM(LTRIM(CONVERT(NVARCHAR(50), SERVERPROPERTY('Edition')))) ,
			@ProductVersion = RTRIM(LTRIM(CONVERT(NVARCHAR(50), SERVERPROPERTY('ProductVersion'))));

	SELECT  @Major = 0;
	SELECT  @Minor = CHARINDEX('.', @ProductVersion, @Major + 1);
	SELECT  @Build = CHARINDEX('.', @ProductVersion, @Minor + 1);
	SELECT  @Revision = CHARINDEX('.', @ProductVersion, @Build + 1);

	SELECT  @Major = CAST(SUBSTRING(@ProductVersion, @Major, @Minor) AS INT);
	SELECT  @Minor = CAST(SUBSTRING(@ProductVersion, @Minor + 1,
									@Build - @Minor - 1) AS INT);
	SELECT  @Build = CASE WHEN @Revision > 0
						  THEN CAST(SUBSTRING(@ProductVersion, @Build + 1,
											  @Revision - @Build - 1) AS INT)
						  ELSE CAST(SUBSTRING(@ProductVersion, @Build + 1,
											  LEN(@ProductVersion) - @Build) AS INT)
					 END;
	SELECT  @Revision = CASE WHEN @Revision > 0
							 THEN CAST(SUBSTRING(@ProductVersion, @Revision + 1,
												 LEN(@ProductVersion) - @Revision) AS INT)
							 ELSE 0
						END;

	-- check version and adjust setting if possible
	IF ( ( @Major = 10
		   AND @ProductEdition = 'Enterprise Edition'
		 )
		 OR ( @Major >= 10 )
	   )
		BEGIN
			EXEC sys.sp_configure 'backup compression default', '1';

			RECONFIGURE;
		END;
	GO

-- 5. Add triggers to msdb
	USE msdb;
	GO

	CREATE TABLE dbo.SQLJobActivationHistory
		(
		  EventRowID BIGINT IDENTITY(1, 1)
							NOT NULL ,
		  EventTime DATETIME NULL ,
		  HostName NVARCHAR(256) NULL ,
		  Instance NVARCHAR(256) NULL ,
		  JobName NVARCHAR(256) NULL ,
		  [Enabled] BIT NULL ,
		  [Message] NVARCHAR(256) NULL ,
		  AuditUser NVARCHAR(256) NULL ,
		  SessionLoginName NVARCHAR(256) NULL ,
		  AuditDate SMALLDATETIME NOT NULL ,
		  CONSTRAINT PK_SQLJobActivationHistory_EventRowID PRIMARY KEY NONCLUSTERED
			( EventRowID ASC )
		);

	CREATE TABLE dbo.SQLJobModificationHistory
		(
		  EventRowID BIGINT IDENTITY(1, 1)
							NOT NULL ,
		  EventTime DATETIME NULL ,
		  EventType VARCHAR(128) NULL ,
		  HostName VARCHAR(128) NULL ,
		  Instance VARCHAR(128) NULL ,
		  JobID VARCHAR(256) NULL ,
		  JobName VARCHAR(256) NULL ,
		  OldJobName VARCHAR(256) NULL ,
		  JobCreationDate DATETIME NOT NULL ,
		  JobModificationDate DATETIME NOT NULL ,
		  AuditUser VARCHAR(128) NULL ,
		  SessionLoginName VARCHAR(256) NULL ,
		  AuditDate SMALLDATETIME NOT NULL ,
		  CONSTRAINT PK_SQLJobModificationHistory_EventRowID PRIMARY KEY NONCLUSTERED
			( EventRowID ASC )
		);

	ALTER TABLE [dbo].[SQLJobActivationHistory] ADD  CONSTRAINT [DF_SQLJobActivationHistory_SessionLoginName]  DEFAULT (ORIGINAL_LOGIN()) FOR [SessionLoginName];

	ALTER TABLE [dbo].[SQLJobActivationHistory] ADD  CONSTRAINT [DF_SQLJobActivationHistory_AuditDate]  DEFAULT (GETDATE()) FOR [AuditDate];

	ALTER TABLE [dbo].[SQLJobModificationHistory] ADD  CONSTRAINT [DF_SQLJobModificationHistory_SessionLoginName]  DEFAULT (ORIGINAL_LOGIN()) FOR [SessionLoginName];

	ALTER TABLE [dbo].[SQLJobModificationHistory] ADD  CONSTRAINT [DF_SQLJobModificationHistory_AuditDate]  DEFAULT (GETDATE()) FOR [AuditDate];
	GO

	CREATE TRIGGER [dbo].[AuditDeletedSQLAgentJobTrigger] ON [msdb].[dbo].[sysjobs]
		FOR DELETE 
	 /*
	 * Stored Procedure: [AuditDeletedSQLAgentJobTrigger] **
	 * Version #: v1.0.0 **
	 * **
	 * Purpose/Comments **
	 * ================ **
	 * Trigger to monitor all deletion events of SQL Agent jobs. **
	 ** * **
	 */
	AS
		BEGIN 
 
			BEGIN TRY
 
				BEGIN TRANSACTION;
				SET NOCOUNT ON; 
 
				DECLARE @UserName [VARCHAR](256) ,
					@SessionLogin [VARCHAR](128) ,
					@HostName [VARCHAR](128) ,
					@JobID [VARCHAR](256) ,
					@JobName [VARCHAR](256) ,
					@SQLInstance [VARCHAR](128) ,
					@DateJobCreated [DATETIME] ,
					@DateJobModified [DATETIME];
 
				SELECT  @UserName = SYSTEM_USER;
				SELECT  @SessionLogin = ORIGINAL_LOGIN();
				SELECT  @HostName = HOST_NAME(); 
				SELECT  @JobID = [job_id]
				FROM    Deleted; 
				SELECT  @JobName = [name]
				FROM    Deleted;
				SELECT  @SQLInstance = CONVERT([VARCHAR](128), SERVERPROPERTY('ServerName'));
				SELECT  @DateJobCreated = [date_created]
				FROM    Deleted;
				SELECT  @DateJobModified = [date_modified]
				FROM    Deleted;
 
				IF ( SELECT COUNT([name])
					 FROM   [master].[dbo].[sysdatabases]
					 WHERE  [name] IN ( 'msdb' )
							AND [status] & 32 <> 32
							AND [status] & 256 <> 256
							AND [status] & 32768 <> 32768
							AND DATABASEPROPERTYEX([name], 'Status') NOT IN (
							'OFFLINE', 'RESTORING', 'RECOVERING', 'SUSPECT' )
				   ) = 1
					BEGIN
						INSERT  INTO msdb.[dbo].[SQLJobModificationHistory]
								( [EventTime] ,
								  [EventType] ,
								  [HostName] ,
								  [Instance] ,
								  [JobID] ,
								  [JobName] ,
								  [OldJobName] ,
								  [JobCreationDate] ,
								  [JobModificationDate] ,
								  [AuditUser] ,
								  [SessionLoginName]
								)
						VALUES  ( GETDATE() ,
								  'JOB_DELETED' ,
								  @HostName ,
								  @SQLInstance ,
								  @JobID ,
								  @JobName ,
								  '-- Not Applicable --' ,
								  @DateJobCreated ,
								  @DateJobModified ,
								  @UserName ,
								  @SessionLogin
								);
					END;
				COMMIT TRANSACTION;
			END TRY 
 
			BEGIN CATCH 
	 -- Test whether the transaction is uncommittable.
				IF ( XACT_STATE() ) = -1
					BEGIN
						PRINT N'The transaction is in an uncommittable state. '
							+ 'Rolling back transaction.';
						ROLLBACK TRANSACTION;
					END;
	 -- Test whether the transaction is active and valid.
				IF ( XACT_STATE() ) = 1
					BEGIN
						PRINT N'The transaction is committable. '
							+ 'Committing transaction.';
						COMMIT TRANSACTION; 
					END;
 
				DECLARE @ErrorMessage [NVARCHAR](4000);
				DECLARE @ErrorSeverity [INT];
				DECLARE @ErrorState [INT];
 
				SELECT  @ErrorMessage = ERROR_MESSAGE() ,
						@ErrorSeverity = ERROR_SEVERITY() ,
						@ErrorState = ERROR_STATE();
 
	-- RAISERROR inside the CATCH block to return error
	 -- information about the original error that caused
	 -- execution to jump to the CATCH block.
				RAISERROR (@ErrorMessage, -- Message text.
	 @ErrorSeverity, -- Severity.
	 @ErrorState ); -- State.
			END CATCH; 
		END;

	GO

	CREATE TRIGGER [dbo].[AuditModifiedSQLAgentJobTrigger] ON [msdb].[dbo].[sysjobs]
		FOR UPDATE 
	 /*
	 * Stored Procedure: [AuditModifiedSQLAgentJobTrigger] **
	 * Version #: v1.0.0 **
	 * **
	 * Purpose/Comments **
	 * ================ **
	 * Trigger to monitor all SQL Agent job modification events. ** 
	 ** * **
	 */
	AS
		BEGIN 
 
			BEGIN TRY
 
				BEGIN TRANSACTION;
				SET NOCOUNT ON; 
				DECLARE @UserName [VARCHAR](256) ,
					@SessionLogin [VARCHAR](128) ,
					@HostName [VARCHAR](128) ,
					@JobID [VARCHAR](256) ,
					@JobName [VARCHAR](256) ,
					@OldJobName [VARCHAR](256) ,
					@SQLInstance [VARCHAR](128) ,
					@DateJobCreated [DATETIME] ,
					@DateJobModified [DATETIME];
 
				SELECT  @UserName = SYSTEM_USER;
				SELECT  @SessionLogin = ORIGINAL_LOGIN();
				SELECT  @HostName = HOST_NAME(); 
				SELECT  @JobID = [job_id]
				FROM    Inserted; 
				SELECT  @JobName = [name]
				FROM    Inserted; 
				SELECT  @OldJobName = [name]
				FROM    Deleted;
				SELECT  @SQLInstance = CONVERT([VARCHAR](128), SERVERPROPERTY('ServerName'));
				SELECT  @DateJobCreated = [date_created]
				FROM    Inserted;
				SELECT  @DateJobModified = [date_modified]
				FROM    Inserted;
				IF ( SELECT COUNT([name])
					 FROM   [master].[dbo].[sysdatabases]
					 WHERE  [name] IN ( 'msdb' )
							AND [status] & 32 <> 32
							AND [status] & 256 <> 256
							AND [status] & 32768 <> 32768
							AND DATABASEPROPERTYEX([name], 'Status') NOT IN (
							'OFFLINE', 'RESTORING', 'RECOVERING', 'SUSPECT' )
				   ) = 1
					BEGIN
						INSERT  INTO msdb.[dbo].[SQLJobModificationHistory]
								( [EventTime] ,
								  [EventType] ,
								  [HostName] ,
								  [Instance] ,
								  [JobID] ,
								  [JobName] ,
								  [OldJobName] ,
								  [JobCreationDate] ,
								  [JobModificationDate] ,
								  [AuditUser] ,
								  [SessionLoginName]
								)
						VALUES  ( GETDATE() ,
								  'JOB_MODIFIED' ,
								  @HostName ,
								  @SQLInstance ,
								  @JobID ,
								  @JobName ,
								  @OldJobName ,
								  @DateJobCreated ,
								  @DateJobModified ,
								  @UserName ,
								  @SessionLogin
								);
					END;
				COMMIT TRANSACTION;
			END TRY 
 
			BEGIN CATCH 
	 -- Test whether the transaction is uncommittable.
				IF ( XACT_STATE() ) = -1
					BEGIN
						PRINT N'The transaction is in an uncommittable state. '
							+ 'Rolling back transaction.';
						ROLLBACK TRANSACTION;
					END;
	 -- Test whether the transaction is active and valid.
				IF ( XACT_STATE() ) = 1
					BEGIN
						PRINT N'The transaction is committable. '
							+ 'Committing transaction.';
						COMMIT TRANSACTION; 
					END;
 
				DECLARE @ErrorMessage [NVARCHAR](4000);
				DECLARE @ErrorSeverity [INT];
				DECLARE @ErrorState [INT];
 
				SELECT  @ErrorMessage = ERROR_MESSAGE() ,
						@ErrorSeverity = ERROR_SEVERITY() ,
						@ErrorState = ERROR_STATE();
 
	-- RAISERROR inside the CATCH block to return error
	 -- information about the original error that caused
	 -- execution to jump to the CATCH block.
				RAISERROR (@ErrorMessage, -- Message text.
	 @ErrorSeverity, -- Severity.
	 @ErrorState ); -- State.
			END CATCH; 
		END;

	GO

	/****** Object:  Trigger [dbo].[AuditNewSQLAgentJobTrigger]    Script Date: 12/22/2015 1:52:03 PM ******/
	SET ANSI_NULLS ON;
	GO

	SET QUOTED_IDENTIFIER ON;
	GO

	CREATE TRIGGER [dbo].[AuditNewSQLAgentJobTrigger] ON [msdb].[dbo].[sysjobs]
		FOR INSERT 
	 /*
	 * Stored Procedure: [AuditNewSQLAgentJobTrigger] **
	 * Version #: v1.0.0 **
	 * **
	 * Purpose/Comments **
	 * ================ **
	 * Trigger to monitor all SQL Agent job creation events. **
	 ** * **
	 */
	AS
		BEGIN 
 
			BEGIN TRY
 
				BEGIN TRANSACTION;
				SET NOCOUNT ON; 
				DECLARE @UserName [VARCHAR](256) ,
					@SessionLogin [VARCHAR](128) ,
					@HostName [VARCHAR](128) ,
					@JobID [VARCHAR](256) ,
					@JobName [VARCHAR](256) ,
					@OldJobName [VARCHAR](256) ,
					@SQLInstance [VARCHAR](128) ,
					@DateJobCreated [DATETIME] ,
					@DateJobModified [DATETIME];
 
				SELECT  @UserName = SYSTEM_USER;
				SELECT  @SessionLogin = ORIGINAL_LOGIN();
				SELECT  @HostName = HOST_NAME(); 
				SELECT  @JobID = [job_id]
				FROM    Inserted; 
				SELECT  @JobName = [name]
				FROM    Inserted; 
				SELECT  @OldJobName = [name]
				FROM    Deleted;
				SELECT  @SQLInstance = CONVERT([VARCHAR](128), SERVERPROPERTY('ServerName'));
				SELECT  @DateJobCreated = [date_created]
				FROM    Inserted;
				SELECT  @DateJobModified = [date_modified]
				FROM    Inserted;
				IF ( SELECT COUNT([name])
					 FROM   [master].[dbo].[sysdatabases]
					 WHERE  [name] IN ( 'msdb' )
							AND [status] & 32 <> 32
							AND [status] & 256 <> 256
							AND [status] & 32768 <> 32768
							AND DATABASEPROPERTYEX([name], 'Status') NOT IN (
							'OFFLINE', 'RESTORING', 'RECOVERING', 'SUSPECT' )
				   ) = 1
					BEGIN
						INSERT  INTO msdb.[dbo].[SQLJobModificationHistory]
								( [EventTime] ,
								  [EventType] ,
								  [HostName] ,
								  [Instance] ,
								  [JobID] ,
								  [JobName] ,
								  [OldJobName] ,
								  [JobCreationDate] ,
								  [JobModificationDate] ,
								  [AuditUser] ,
								  [SessionLoginName]
								)
						VALUES  ( GETDATE() ,
								  'JOB_CREATED' ,
								  @HostName ,
								  @SQLInstance ,
								  @JobID ,
								  @JobName ,
								  @OldJobName ,
								  @DateJobCreated ,
								  @DateJobModified ,
								  @UserName ,
								  @SessionLogin
								);
					END;
				COMMIT TRANSACTION;
			END TRY 
 
			BEGIN CATCH 
	 -- Test whether the transaction is uncommittable.
				IF ( XACT_STATE() ) = -1
					BEGIN
						PRINT N'The transaction is in an uncommittable state. '
							+ 'Rolling back transaction.';
						ROLLBACK TRANSACTION;
					END;
	 -- Test whether the transaction is active and valid.
				IF ( XACT_STATE() ) = 1
					BEGIN
						PRINT N'The transaction is committable. '
							+ 'Committing transaction.';
						COMMIT TRANSACTION; 
					END;
 
				DECLARE @ErrorMessage [NVARCHAR](4000);
				DECLARE @ErrorSeverity [INT];
				DECLARE @ErrorState [INT];
 
				SELECT  @ErrorMessage = ERROR_MESSAGE() ,
						@ErrorSeverity = ERROR_SEVERITY() ,
						@ErrorState = ERROR_STATE();
 
	-- RAISERROR inside the CATCH block to return error
	 -- information about the original error that caused
	 -- execution to jump to the CATCH block.
				RAISERROR (@ErrorMessage, -- Message text.
	 @ErrorSeverity, -- Severity.
	 @ErrorState ); -- State.
			END CATCH; 
		END;

	GO

	/****** Object:  Trigger [dbo].[AuditSQLAgentJobActivationTrigger]    Script Date: 12/22/2015 1:52:03 PM ******/
	SET ANSI_NULLS ON;
	GO

	SET QUOTED_IDENTIFIER ON;
	GO

	CREATE TRIGGER [dbo].[AuditSQLAgentJobActivationTrigger] ON [msdb].[dbo].[sysjobs]
		FOR UPDATE 
	 /* * Stored Procedure: [AuditSQLAgentJobActivationTrigger] **
	 * Version #: v1.0.0 **
	 * **
	 * Purpose/Comments **
	 * ================ **
	 * Trigger to monitor all enable/disable events of SQL Agent jobs. ** 
	 ** *
	 **
	 */
	AS
		BEGIN 
 
			BEGIN TRY
 
				BEGIN TRANSACTION;
				SET NOCOUNT ON; 
				DECLARE @UserName [VARCHAR](256) ,
					@SessionLogin [VARCHAR](128) ,
					@HostName [VARCHAR](128) ,
					@JobName [VARCHAR](256) ,
					@SQLInstance [VARCHAR](128) ,
					@NewEnabled [INT] ,
					@OldEnabled [INT]; 
 
				SELECT  @UserName = SYSTEM_USER;
				SELECT  @SessionLogin = ORIGINAL_LOGIN();
				SELECT  @HostName = HOST_NAME(); 
				SELECT  @JobName = [name]
				FROM    Inserted;
				SELECT  @NewEnabled = [enabled]
				FROM    Inserted; 
				SELECT  @OldEnabled = [enabled]
				FROM    Deleted; 
				SELECT  @SQLInstance = CONVERT([VARCHAR](128), SERVERPROPERTY('ServerName'));
 
	-- check if the enabled flag has been updated. 
				IF @NewEnabled <> @OldEnabled
					BEGIN 
						IF ( SELECT COUNT([name])
							 FROM   [master].[dbo].[sysdatabases]
							 WHERE  [name] IN ( 'msdb' )
									AND [status] & 32 <> 32
									AND [status] & 256 <> 256
									AND [status] & 32768 <> 32768
									AND DATABASEPROPERTYEX([name], 'Status') NOT IN (
									'OFFLINE', 'RESTORING', 'RECOVERING',
									'SUSPECT' )
						   ) = 1
							BEGIN
								IF @NewEnabled = 1
									BEGIN 
										INSERT  INTO msdb.[dbo].[SQLJobActivationHistory]
												( [EventTime] ,
												  [HostName] ,
												  [Instance] ,
												  [JobName] ,
												  [Enabled] ,
												  [Message] ,
												  [AuditUser] ,
												  [SessionLoginName]
												)
										VALUES  ( GETDATE() ,
												  @HostName ,
												  @SQLInstance ,
												  @JobName ,
												  1 ,
												  'Job has been enabled.' ,
												  @UserName ,
												  @SessionLogin
												); 
									END; -- End of inner-IF block... 
								IF @NewEnabled = 0
									BEGIN 
										INSERT  INTO msdb.[dbo].[SQLJobActivationHistory]
												( [EventTime] ,
												  [HostName] ,
												  [Instance] ,
												  [JobName] ,
												  [Enabled] ,
												  [Message] ,
												  [AuditUser] ,
												  [SessionLoginName]
												)
										VALUES  ( GETDATE() ,
												  @HostName ,
												  @SQLInstance ,
												  @JobName ,
												  0 ,
												  'Job has been disabled.' ,
												  @UserName ,
												  @SessionLogin
												);
									END; -- End of inner-IF block...
							END; -- End of outer-IF block...
					END; -- End of outer-IF block...
				COMMIT TRANSACTION;
			END TRY 
 
			BEGIN CATCH 
	 -- Test whether the transaction is uncommittable.
				IF ( XACT_STATE() ) = -1
					BEGIN
						PRINT N'The transaction is in an uncommittable state. '
							+ 'Rolling back transaction.';
						ROLLBACK TRANSACTION;
					END;
	 -- Test whether the transaction is active and valid.
				IF ( XACT_STATE() ) = 1
					BEGIN
						PRINT N'The transaction is committable. '
							+ 'Committing transaction.';
						COMMIT TRANSACTION; 
					END;
 
				DECLARE @ErrorMessage [NVARCHAR](4000);
				DECLARE @ErrorSeverity [INT];
				DECLARE @ErrorState [INT];
 
				SELECT  @ErrorMessage = ERROR_MESSAGE() ,
						@ErrorSeverity = ERROR_SEVERITY() ,
						@ErrorState = ERROR_STATE();
 
	-- RAISERROR inside the CATCH block to return error
	 -- information about the original error that caused
	 -- execution to jump to the CATCH block.
				RAISERROR (@ErrorMessage, -- Message text.
	 @ErrorSeverity, -- Severity.
	 @ErrorState ); -- State.
			END CATCH; 
		END;

	GO

-- 6. Set Trace Flags on Startup
	USE master;
	GO

	IF EXISTS ( SELECT  1
				FROM    sys.procedures
				WHERE   name = 'uspSetServerTraceFlags' )
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
			DECLARE @ProductEdition NVARCHAR(50) ,
				@ProductVersion NVARCHAR(50) ,
				@Major INT ,
				@Minor INT ,
				@Build INT ,
				@Revision INT;
	
			SELECT  @ProductEdition = RTRIM(LTRIM(CONVERT(NVARCHAR(50), SERVERPROPERTY('Edition')))) ,
					@ProductVersion = RTRIM(LTRIM(CONVERT(NVARCHAR(50), SERVERPROPERTY('ProductVersion'))));

			SELECT  @Major = 0;
			SELECT  @Minor = CHARINDEX('.', @ProductVersion, @Major + 1);
			SELECT  @Build = CHARINDEX('.', @ProductVersion, @Minor + 1);
			SELECT  @Revision = CHARINDEX('.', @ProductVersion, @Build + 1);

			SELECT  @Major = CAST(SUBSTRING(@ProductVersion, @Major, @Minor) AS INT);
			SELECT  @Minor = CAST(SUBSTRING(@ProductVersion, @Minor + 1,
											@Build - @Minor - 1) AS INT);
			SELECT  @Build = CASE WHEN @Revision > 0
								  THEN CAST(SUBSTRING(@ProductVersion, @Build + 1,
													  @Revision - @Build - 1) AS INT)
								  ELSE CAST(SUBSTRING(@ProductVersion, @Build + 1,
													  LEN(@ProductVersion)
													  - @Build) AS INT)
							 END;
			SELECT  @Revision = CASE WHEN @Revision > 0
									 THEN CAST(SUBSTRING(@ProductVersion,
														 @Revision + 1,
														 LEN(@ProductVersion)
														 - @Revision) AS INT)
									 ELSE 0
								END;

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
	
			IF ( ( ( @Major = 9 )
				   AND ( @Minor = 0 )
				   AND ( @Build >= 4266 )
				 )	-- Cumulative Update 6 for SQL Server 2005 Service Pack 3
				 OR ( ( @Major = 10 )
					  AND ( @Minor = 0 )
					  AND ( @Build >= 2766 )
					)	-- Cumulative Update 7 for SQL Server 2008 Service Pack 1
				 OR ( ( @Major = 10 )
					  AND ( @Minor = 50 )
					)						-- SQL Server 2008 R2
				 OR ( (@Major = 11) )											-- SQL Server 2012
				 OR ( (@Major = 12) )											-- SQL Server 2014
			   )
				BEGIN
					DBCC TRACEON (4199, -1); -- Enables all the fixes that were previously made for the query processor under many trace flags (KB974006 / http://support.microsoft.com/kb/974006)
				END;

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
		END;
	GO

	---

	USE [master];
	GO

	IF EXISTS ( SELECT  1
				FROM    sys.procedures
				WHERE   name = 'uspEnableTraceFlags' )
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

			SET NOCOUNT ON;
	
			EXECUTE master.[dbo].[uspSetServerTraceFlags];

		END;
	GO

	EXEC sp_procoption N'[dbo].[uspEnableTraceFlags]', 'startup', '1';
	GO

	EXECUTE [master].[dbo].[uspEnableTraceFlags];
	GO

-- 7. Set up database mail
	-- search for <company.mailserver.com> and replace it with your mail server

	-- make sure to change the @TestEmailAccount to whatever account you want to
	-- use as the test receiver

	sp_configure 'advanced options', 1; 
	RECONFIGURE;
	GO
	sp_configure 'Database Mail XPs', 1; 
	RECONFIGURE;
	GO

	DECLARE @ProfileName VARCHAR(200) ,
		@ProfieDescription VARCHAR(8000) ,
		@ProfilePricipleID VARCHAR(10) ,
		@isProfileDefault VARCHAR(2) ,
		@AccountName VARCHAR(200) ,
		@AccountDescription VARCHAR(8000) ,
		@AccountFromEmail VARCHAR(500) ,
		@AccountDisplayName VARCHAR(500) ,
		@AccountReplyEmail VARCHAR(500) ,
		@AccountMailServer VARCHAR(500) ,
		@AccountSquenceNumber VARCHAR(10) ,
		@TestEmailAccount VARCHAR(200) ,
		@ShowServerInfo BIT ,
		@RunDBMailSETup BIT ,
		@RunDBMailTest BIT ,
		@cmd VARCHAR(MAX);
		
	SELECT  @RunDBMailSETup = 1 ,
			@RunDBMailTest = 1 ,
			@ShowServerInfo = 1 ,
			@TestEmailAccount = 'yourEmail@domain.com' , --Plug in YOUR email here...do not use the team DL.
			@ProfileName = CONVERT(VARCHAR(32), CONVERT(VARCHAR(32), LEFT(@@servername,
																  CASE CHARINDEX('\',
																  @@servername)
																  WHEN 0
																  THEN LEN(@@servername)
																  ELSE CHARINDEX('\',
																  @@servername)
																  - 1
																  END))) ,
			@ProfieDescription = '' ,
			@ProfilePricipleID = '0' ,
			@isProfileDefault = '1' ,
			@AccountName = CONVERT(VARCHAR(32), LEFT(@@servername,
													 CASE CHARINDEX('\',
																  @@servername)
													   WHEN 0
													   THEN LEN(@@servername)
													   ELSE CHARINDEX('\',
																  @@servername)
															- 1
													 END)) ,
			@AccountDescription = '' ,
			@AccountFromEmail = CONVERT(VARCHAR(32), LEFT(@@servername,
														  CASE CHARINDEX('\',
																  @@servername)
															WHEN 0
															THEN LEN(@@servername)
															ELSE CHARINDEX('\',
																  @@servername)
																 - 1
														  END)) + '@coyote.com' ,
			@AccountDisplayName = CONVERT(VARCHAR(32), @@servername) ,
			@AccountReplyEmail = '' ,
			@AccountMailServer = '<company.mailserver.com>' ,
			@AccountSquenceNumber = '1';
		
	IF ( @RunDBMailSETup = 1 )
		BEGIN
			EXEC msdb.dbo.sysmail_add_profile_sp @profile_name = @ProfileName,
				@description = @AccountDescription;

			EXEC msdb.dbo.sysmail_add_principalprofile_sp @profile_name = @ProfileName,
				@principal_id = @ProfilePricipleID,
				@is_default = @isProfileDefault;

			EXEC msdb.dbo.sysmail_add_account_sp @account_name = @AccountName,
				@description = @ProfieDescription,
				@email_address = @AccountFromEmail,
				@replyto_address = @AccountReplyEmail,
				@display_name = @AccountDisplayName,
				@mailserver_name = @AccountMailServer;

			EXEC msdb.dbo.sysmail_add_profileaccount_sp @profile_name = @ProfileName,
				@account_name = @AccountName,
				@sequence_number = @AccountSquenceNumber;

	
			EXEC msdb.dbo.sp_set_sqlagent_properties @email_profile = @ProfileName,
				@databasemail_profile = @ProfileName,
				@email_save_in_sent_folder = 1, @use_databasemail = 1;

		END;

	IF ( @ShowServerInfo = 1 )
		BEGIN
			SELECT  'Profile Info' ,
					*
			FROM    msdb.dbo.sysmail_profile p
					LEFT JOIN msdb.dbo.sysmail_principalprofile pp ON p.profile_id = pp.profile_id;

			SELECT  'Server info' ,
					*
			FROM    msdb.dbo.sysmail_account a
					LEFT JOIN msdb.dbo.sysmail_server s ON a.account_id = s.account_id;

			SELECT  'Profile + Account Info' ,
					p.* ,
					a.*
			FROM    msdb.dbo.sysmail_profile p
					JOIN msdb.dbo.sysmail_profileaccount pa ON p.profile_id = pa.profile_id
					JOIN msdb.dbo.sysmail_account a ON pa.account_id = a.account_id;
		END;



	IF ( @RunDBMailTest = 1 )
		BEGIN
			DECLARE @Body NVARCHAR(MAX);
			SELECT  @Body = 'This is a test e-mail sent from Database Mail on '
					+ @@SERVERNAME + '.';
			EXEC msdb.dbo.sp_send_dbmail @profile_name = @ProfileName,
				@recipients = @TestEmailAccount, @subject = 'Database Mail Test',
				@body = @Body;
		END;

-- 8. Set up basic server alerts. Prod version and non-prod version
--MessageIds 823, 824, 825, 832, 9100
--Severities 16-25
	USE [msdb];

	-- Create the Operators
	IF NOT EXISTS ( SELECT  1
					FROM    msdb.dbo.sysoperators
					WHERE   NAME = 'DBAPager' )
		BEGIN
			EXEC msdb.dbo.sp_add_operator @name = N'DBAPager', @enabled = 1,
				@email_address = N'<email address for dba pager and dba team>';
		END;
	GO

	IF NOT EXISTS ( SELECT  1
					FROM    msdb.dbo.sysoperators
					WHERE   NAME = 'DBAAlerts' )
		BEGIN
			EXEC msdb.dbo.sp_add_operator @name = N'DBAAlerts', @enabled = 1,
				@email_address = N'<email address for dba team>';
		END;
	GO

	IF NOT EXISTS ( SELECT  1
					FROM    msdb.dbo.sysoperators
					WHERE   NAME = 'SQLPager' )
		BEGIN
			EXEC msdb.dbo.sp_add_operator @name = N'SQLPager', @enabled = 1,
				@email_address = N'<email addresses for dba team pager, dba team, and server team>';
		END;
	GO

	IF NOT EXISTS ( SELECT  1
					FROM    msdb.dbo.sysoperators
					WHERE   NAME = 'SQLAlerts' )
		BEGIN
			EXEC msdb.dbo.sp_add_operator @name = N'SQLAlerts', @enabled = 1,
				@email_address = N'<email addresses for dba team and server team>';
		END;
	GO

	USE [msdb];
	GO

	EXEC master.dbo.sp_MSsetalertinfo @failsafeoperator = N'DBAAlerts',
		@notificationmethod = 1;
	GO

	/***********************************************
	-- Drop and recreate alerts according to Coyote standards
	************************************************/
	DECLARE @oldAlertName SYSNAME;
	DECLARE @pageOperator SYSNAME;
	DECLARE @seEmailOperator SYSNAME;
	DECLARE @sePageOperator SYSNAME;
	DECLARE @emailOperator SYSNAME;

	SET @pageOperator = 'DBAPager';
	SET @emailOperator = 'DBAAlerts';
	SET @sePageOperator = 'SQLPager';
	SET @seEmailOperator = 'SQLAlerts';



	-- Fatal Error - 823 (Hard I/O Error)
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 823
						AND severity = 0 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 823
					AND severity = 0;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - 823 (Hard I/O Error)',
		@message_id = 823, @severity = 0, @enabled = 1,
		@delay_between_responses = 600, @include_event_description_in = 1,
		@notification_message = N'This is where SQL Server has asked the OS to read the page but it cant',
		@category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - 823 (Hard I/O Error)',
		@operator_name = @seEmailOperator, @notification_method = 1;

	-- Fatal Error - 824 (Soft I/O Error)
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 824
						AND severity = 0 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 824
					AND severity = 0;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - 824 (Soft I/O Error)',
		@message_id = 824, @severity = 0, @enabled = 1,
		@delay_between_responses = 600, @include_event_description_in = 1,
		@notification_message = N'This is where the OS could read the page but SQL Server decided that the page was corrupt - for example with a page checksum failure',
		@category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - 824 (Soft I/O Error)',
		@operator_name = @seEmailOperator, @notification_method = 1;

	-- Fatal Error - 825 (Read/Retry I/O Error)
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 825
						AND severity = 0 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 825
					AND severity = 0;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - 825 (Read/Retry I/O Error)',
		@message_id = 825, @severity = 0, @enabled = 1,
		@delay_between_responses = 600, @include_event_description_in = 1,
		@notification_message = N'This is where either an 823 or 824 occured, SQL server retried the IO automatically and it succeeded. This error is written to the errorlog only - you need to be aware of these as they''re a sign of the IO subsystem going awry. There''s no way to turn off read-retry and force SQL Server to ''fail-fast.''',
		@category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - 825 (Read/Retry I/O Error)',
		@operator_name = @seEmailOperator, @notification_method = 1;

	-- Fatal Error - 832 (Memory Error)
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 832
						AND severity = 0 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 832
					AND severity = 0;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - 832 (Memory Error)',
		@message_id = 832, @severity = 0, @enabled = 1,
		@delay_between_responses = 600, @include_event_description_in = 1,
		@notification_message = N'A page that should have been constant has changed. This usually indicates a memory failure or other hardware or OS corruption.',
		@category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - 832 (Memory Error)',
		@operator_name = @seEmailOperator, @notification_method = 1;

	-- Error - 9100 (Index Corruption)
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 9100
						AND severity = 0 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 9100
					AND severity = 0;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Error - 9100 (Index Corruption)',
		@message_id = 9100, @severity = 0, @enabled = 1,
		@delay_between_responses = 600, @include_event_description_in = 1,
		@notification_message = N'Possible index corruption detected. Run DBCC CHECKDB.',
		@category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Error - 9100 (Index Corruption)',
		@operator_name = @emailOperator, @notification_method = 1;

	-- Error - Miscellaneous User Error
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 0
						AND severity = 16 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 0
					AND severity = 16;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Error - Miscellaneous User Error',
		@message_id = 0, @severity = 16, @enabled = 1,
		@delay_between_responses = 600, @include_event_description_in = 1,
		@notification_message = N'', @category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Error - Miscellaneous User Error',
		@operator_name = @emailOperator, @notification_method = 1;

	-- Error - Insufficient Resources
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 0
						AND severity = 17 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 0
					AND severity = 17;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Error - Insufficient Resources',
		@message_id = 0, @severity = 17, @enabled = 1,
		@delay_between_responses = 600, @include_event_description_in = 1,
		@notification_message = N'', @category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Error - Insufficient Resources',
		@operator_name = @emailOperator, @notification_method = 1;

	-- Error - Internal
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 0
						AND severity = 18 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 0
					AND severity = 18;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Error - Internal', @message_id = 0,
		@severity = 18, @enabled = 1, @delay_between_responses = 600,
		@include_event_description_in = 1, @notification_message = N'',
		@category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Error - Internal',
		@operator_name = @emailOperator, @notification_method = 1;

	-- Fatal Error - Resource
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 0
						AND severity = 19 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 0
					AND severity = 19;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Resource', @message_id = 0,
		@severity = 19, @enabled = 1, @delay_between_responses = 600,
		@include_event_description_in = 1, @notification_message = N'',
		@category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Resource',
		@operator_name = @emailOperator, @notification_method = 1;

	-- Fatal Error - Current Process
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 0
						AND severity = 20 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 0
					AND severity = 20;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Current Process',
		@message_id = 0, @severity = 20, @enabled = 1,
		@delay_between_responses = 600, @include_event_description_in = 1,
		@notification_message = N'', @category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Current Process',
		@operator_name = @emailOperator, @notification_method = 1;

	-- Fatal Error - Database Process
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 0
						AND severity = 21 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 0
					AND severity = 21;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Database Process',
		@message_id = 0, @severity = 21, @enabled = 1,
		@delay_between_responses = 600, @include_event_description_in = 1,
		@notification_message = N'', @category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Database Process',
		@operator_name = @emailOperator, @notification_method = 1;

	-- Fatal Error - Table Integrity
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 0
						AND severity = 22 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 0
					AND severity = 22;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Table Integrity',
		@message_id = 0, @severity = 22, @enabled = 1,
		@delay_between_responses = 600, @include_event_description_in = 1,
		@notification_message = N'', @category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Table Integrity',
		@operator_name = @emailOperator, @notification_method = 1;

	-- Fatal Error - Database Integrity
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 0
						AND severity = 23 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 0
					AND severity = 23;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Database Integrity',
		@message_id = 0, @severity = 23, @enabled = 1,
		@delay_between_responses = 600, @include_event_description_in = 1,
		@notification_message = N'', @category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Database Integrity',
		@operator_name = @pageOperator, @notification_method = 1;

	-- Fatal Error - Hardware Error
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 0
						AND severity = 24 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 0
					AND severity = 24;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Hardware Error',
		@message_id = 0, @severity = 24, @enabled = 1,
		@delay_between_responses = 600, @include_event_description_in = 1,
		@notification_message = N'', @category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Hardware Error',
		@operator_name = @sePageOperator, @notification_method = 1;

	-- Fatal Error - Miscellaneous
	IF EXISTS ( SELECT  1
				FROM    msdb.dbo.sysalerts
				WHERE   message_id = 0
						AND severity = 25 )
		BEGIN
			SELECT  @oldAlertName = NAME
			FROM    msdb.dbo.sysalerts
			WHERE   message_id = 0
					AND severity = 25;

			EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
		END;

	EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Miscellaneous',
		@message_id = 0, @severity = 25, @enabled = 1,
		@delay_between_responses = 600, @include_event_description_in = 1,
		@notification_message = N'', @category_name = N'[Uncategorized]',
		@job_id = N'00000000-0000-0000-0000-000000000000';

	-- Add Notification
	EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Miscellaneous',
		@operator_name = @emailOperator, @notification_method = 1;

-- 9. Test job failure alerts
	USE [msdb];
	GO

	/****** Object:  Job [test]    Script Date: 1/23/2016 8:32:46 AM ******/
	BEGIN TRANSACTION;
	DECLARE @ReturnCode INT;
	SELECT  @ReturnCode = 0;
	/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 1/23/2016 8:32:46 AM ******/
	IF NOT EXISTS ( SELECT  name
					FROM    msdb.dbo.syscategories
					WHERE   name = N'[Uncategorized (Local)]'
							AND category_class = 1 )
		BEGIN
			EXEC @ReturnCode = msdb.dbo.sp_add_category @class = N'JOB',
				@type = N'LOCAL', @name = N'[Uncategorized (Local)]';
			IF ( @@ERROR <> 0
				 OR @ReturnCode <> 0
			   )
				GOTO QuitWithRollback;

		END;

	DECLARE @jobId BINARY(16);
	EXEC @ReturnCode = msdb.dbo.sp_add_job @job_name = N'test', @enabled = 1,
		@notify_level_eventlog = 0, @notify_level_email = 2,
		@notify_level_netsend = 0, @notify_level_page = 0, @delete_level = 0,
		@description = N'No description available.',
		@category_name = N'[Uncategorized (Local)]', @owner_login_name = N'sa',
		@notify_email_operator_name = N'DBAAlerts', @job_id = @jobId OUTPUT;
	IF ( @@ERROR <> 0
		 OR @ReturnCode <> 0
	   )
		GOTO QuitWithRollback;
	/****** Object:  Step [test]    Script Date: 1/23/2016 8:32:46 AM ******/
	EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id = @jobId,
		@step_name = N'test', @step_id = 1, @cmdexec_success_code = 0,
		@on_success_action = 1, @on_success_step_id = 0, @on_fail_action = 2,
		@on_fail_step_id = 0, @retry_attempts = 0, @retry_interval = 0,
		@os_run_priority = 0, @subsystem = N'TSQL',
		@command = N'select 1 from test', @database_name = N'master', @flags = 0;
	IF ( @@ERROR <> 0
		 OR @ReturnCode <> 0
	   )
		GOTO QuitWithRollback;
	EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1;
	IF ( @@ERROR <> 0
		 OR @ReturnCode <> 0
	   )
		GOTO QuitWithRollback;
	EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId,
		@server_name = N'(local)';
	IF ( @@ERROR <> 0
		 OR @ReturnCode <> 0
	   )
		GOTO QuitWithRollback;
	COMMIT TRANSACTION;
	GOTO EndSave;
	QuitWithRollback:
	IF ( @@TRANCOUNT > 0 )
		ROLLBACK TRANSACTION;
	EndSave:

	GO

	EXEC msdb.dbo.sp_start_job @job_name = 'test';
	GO

	WAITFOR DELAY '00:00:10.000';

	EXEC msdb.dbo.sp_delete_job @job_name = 'test';
	GO

-- 10. Job to cycle error log
	--Creates a job that cycles the error log once a month on the 1st
	--Replace:
	--	<DBA Category Name>
	--	<DBA Email Alert Operator>

	USE [msdb];
	GO

	BEGIN TRANSACTION;
	DECLARE @ReturnCode INT;
	SELECT  @ReturnCode = 0;

	IF NOT EXISTS ( SELECT  name
					FROM    msdb.dbo.syscategories
					WHERE   name = N'<DBA Category Name>'
							AND category_class = 1 )
		BEGIN
			EXEC @ReturnCode = msdb.dbo.sp_add_category @class = N'JOB',
				@type = N'LOCAL', @name = N'<DBA Category Name>';
			IF ( @@ERROR <> 0
				 OR @ReturnCode <> 0
			   )
				GOTO QuitWithRollback;

		END;

	DECLARE @jobId BINARY(16);
	EXEC @ReturnCode = msdb.dbo.sp_add_job @job_name = N'__DB_sp_cycle_errorlog',
		@enabled = 1, @notify_level_eventlog = 0, @notify_level_email = 2,
		@notify_level_netsend = 0, @notify_level_page = 0, @delete_level = 0,
		@description = N'No description available.',
		@category_name = N'<DBA Category Name>', @owner_login_name = N'sa',
		@notify_email_operator_name = N'<DBA Email Alert Operator>',
		@job_id = @jobId OUTPUT;
	IF ( @@ERROR <> 0
		 OR @ReturnCode <> 0
	   )
		GOTO QuitWithRollback;

	EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id = @jobId,
		@step_name = N'Call SP sp_cycle_errorlog', @step_id = 1,
		@cmdexec_success_code = 0, @on_success_action = 1, @on_success_step_id = 0,
		@on_fail_action = 2, @on_fail_step_id = 0, @retry_attempts = 0,
		@retry_interval = 0, @os_run_priority = 0, @subsystem = N'TSQL',
		@command = N'EXEC sp_cycle_errorlog', @database_name = N'master',
		@flags = 0;
	IF ( @@ERROR <> 0
		 OR @ReturnCode <> 0
	   )
		GOTO QuitWithRollback;
	EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1;
	IF ( @@ERROR <> 0
		 OR @ReturnCode <> 0
	   )
		GOTO QuitWithRollback;
	EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id = @jobId,
		@name = N'__DB_sp_cycle_errorlog', @enabled = 1, @freq_type = 16,
		@freq_interval = 1, @freq_subday_type = 1, @freq_subday_interval = 0,
		@freq_relative_interval = 0, @freq_recurrence_factor = 1,
		@active_start_date = 20120101, @active_end_date = 99991231,
		@active_start_time = 0, @active_end_time = 235959;
	IF ( @@ERROR <> 0
		 OR @ReturnCode <> 0
	   )
		GOTO QuitWithRollback;
	EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId,
		@server_name = N'(local)';
	IF ( @@ERROR <> 0
		 OR @ReturnCode <> 0
	   )
		GOTO QuitWithRollback;
	COMMIT TRANSACTION;
	GOTO EndSave;
	QuitWithRollback:
	IF ( @@TRANCOUNT > 0 )
		ROLLBACK TRANSACTION;
	EndSave:

	GO

-- 11. Verify server time
	SELECT  GETDATE();

-- 12. Set model recovery to simple
	USE [master];
	GO
	ALTER DATABASE [model] SET RECOVERY SIMPLE;
	GO
	SELECT  recovery_model_desc
	FROM    sys.databases
	WHERE   DB_NAME(database_id) = 'model';

-- 13. Configure tempdb files
	--Check the number of CPUs
	SELECT  cpu_count
	FROM    sys.dm_os_sys_info;

	--Move tempdb and set the number of files = number of logical cores
	--If more than 8 logical cores, start with 8 files
	--****** MAKE SURE TO ADJUST FILE SIZES ******
	USE [master];
	GO
	ALTER DATABASE tempdb MODIFY FILE ( NAME = 'tempdev', FILENAME = N'T:\Data\tempdb.mdf', SIZE = 8192MB , FILEGROWTH = 256MB );
	GO
	ALTER DATABASE tempdb MODIFY FILE ( NAME = 'templog', FILENAME = N'T:\Log\templog.ldf', SIZE = 5120MB , FILEGROWTH = 512MB );
	GO
	--add additional data files
	ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev2', FILENAME = N'T:\DATA\tempdb2.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB );
	GO
	ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev3', FILENAME = N'T:\DATA\tempdb3.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB );
	GO
	ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev4', FILENAME = N'T:\DATA\tempdb4.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB );
	GO
	ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev5', FILENAME = N'T:\DATA\tempdb5.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB );
	GO
	ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev6', FILENAME = N'T:\DATA\tempdb6.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB );
	GO
	ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev7', FILENAME = N'T:\DATA\tempdb7.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB );
	GO
	ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev8', FILENAME = N'T:\DATA\tempdb8.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB );
	GO

-- 14. Adjust SQL Agent history
	SELECT  *
	FROM    sys.dm_server_registry
	WHERE   value_name IN ( 'JobHistoryMaxRows', 'JobHistoryMaxRowsPerJob' );
	EXEC msdb.dbo.sp_set_sqlagent_properties @jobhistory_max_rows = 100000,
		@jobhistory_max_rows_per_job = 1000;
	SELECT  *
	FROM    sys.dm_server_registry
	WHERE   value_name IN ( 'JobHistoryMaxRows', 'JobHistoryMaxRowsPerJob' );

-- 15. Adjust error logs to 12
	DECLARE @RegSetting INT;
 
	--SHOULD BE 12
	EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',
		N'Software\Microsoft\MSSQLServer\MSSQLServer', N'NumErrorLogs',
		@RegSetting OUTPUT;
	SELECT  @RegSetting NumErrorLogs;
	EXEC master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE',
		N'Software\Microsoft\MSSQLServer\MSSQLServer', N'NumErrorLogs', REG_DWORD,
		12;
	EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',
		N'Software\Microsoft\MSSQLServer\MSSQLServer', N'NumErrorLogs',
		@RegSetting OUTPUT;
	SELECT  @RegSetting NumErrorLogs;
	GO

-- 16. Change master and model filegrowth settings
	--This script will change the file growth to MB growth and unlimited growth for master and msdb.
	DECLARE @string VARCHAR(512) ,
		@file VARCHAR(512);

	--master
	SET @file = ( SELECT    name
				  FROM      master.sys.master_files
				  WHERE     file_id = 1
							AND DB_NAME(database_id) = 'master'
				);

	SET @string = 'alter database [master] modify file (name=' + @file
		+ ', maxsize=unlimited, filegrowth=1024MB);';
	PRINT ( @string );
	EXEC (@string);

	--msdb
	SET @file = ( SELECT    name
				  FROM      master.sys.master_files
				  WHERE     file_id = 1
							AND DB_NAME(database_id) = 'msdb'
				);

	SET @string = 'alter database [msdb] modify file (name=' + @file
		+ ', maxsize=unlimited, filegrowth=1024MB);';
	PRINT ( @string );
	EXEC (@string);

-- 17. Change database owners all to sa
	SELECT  CASE WHEN is_read_only = 1
				 THEN 'ALTER DATABASE [' + name + '] SET READ_WRITE' + CHAR(10)
					  + 'GO' + CHAR(10)
				 ELSE ''
			END + 'ALTER AUTHORIZATION ON DATABASE::[' + name + '] TO sa;'
			+ CHAR(10) + 'GO' + CHAR(10)
			+ CASE WHEN is_read_only = 1
				   THEN 'ALTER DATABASE [' + name + '] SET READ_ONLY' + CHAR(10)
						+ 'GO' + CHAR(10)
				   ELSE ''
			  END AS Script ,
			SUSER_SNAME(owner_sid) AS CurrentOwner
	FROM    sys.databases WITH ( NOLOCK )
	WHERE   name NOT IN ( 'master', 'model', 'msdb', 'tempdb' )
			AND SUSER_SNAME(owner_sid) <> 'sa'
			AND state = 0
	ORDER BY name;

-- 18. Verifry settings and error logs
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
	IF EXISTS ( SELECT  *
				FROM    ::
						fn_virtualservernodes() )
		BEGIN
			PRINT ( 'Cluster nodes below' );
			SELECT  *
			FROM    ::
					fn_virtualservernodes();
		END;
	ELSE
		PRINT ( 'NOT CLUSTERED' );


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
	SET NOCOUNT ON;

	CREATE TABLE #xp ( txtOut VARCHAR(1024) );

	DECLARE @auth_scheme NVARCHAR(40) ,
		@auth_scheme2 NVARCHAR(40) ,
		@ServiceAccountName VARCHAR(320) ,
		@cmd VARCHAR(1024) ,
		@xp_check INT;

	SELECT  @auth_scheme = auth_scheme
	FROM    sys.dm_exec_connections
	WHERE   session_id = @@spid;

	IF @auth_scheme <> 'KERBEROS'
		BEGIN
			SELECT  @auth_scheme2 = @auth_scheme;
			SELECT  @auth_scheme = auth_scheme
			FROM    sys.dm_exec_connections
			WHERE   auth_scheme = 'KERBEROS';
			IF @auth_scheme <> 'KERBEROS'
				BEGIN
					SELECT  'No connections are currently using KERBEROS.';

					EXEC sys.xp_readerrorlog 0, 1, N'Service Principal Name';

					EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',
						N'SYSTEM\CurrentControlSet\Services\MSSQLSERVER',
						N'ObjectName', @ServiceAccountName OUTPUT, N'no_output';

					SELECT  @cmd = 'SETSPN -l ' + @ServiceAccountName;

					INSERT  INTO #xp
							EXEC sys.xp_cmdshell @cmd;

					SELECT  txtOut AS [SETSPN -l AccountName]
					FROM    #xp
					WHERE   txtOut IS NOT NULL;
				END;
			ELSE
				SELECT  'KERBEROS is currently working, however you are currently authenticated using '
						+ @auth_scheme2 + ' authentication.';
		END;
	ELSE
		BEGIN
			SELECT  'You are currently authenticated using KERBEROS.';
		END;

	DROP TABLE #xp;

	SET NOCOUNT OFF;


	--EXAMINE ERROR LOG
	EXEC xp_readerrorlog 0, 1;

-- 19. Disable xp_xmdshell
	--If not doing a side-by-side where xp_cmdshell is already enabled on the source server...
	EXEC sys.sp_configure 'Advanced Options', 1;
	RECONFIGURE WITH OVERRIDE;
	EXEC sys.sp_configure 'xp_cmdshell', 0;
	RECONFIGURE WITH OVERRIDE;

-- 20. Randomize sa password and disable login
	DECLARE @Password VARCHAR(50) ,
		@SQL VARCHAR(512) ,
		@PServer VARCHAR(128);

	SELECT  @PServer = @@servername;

	SELECT  @@SERVERNAME;

	IF EXISTS ( SELECT  1
				FROM    sys.server_principals
				WHERE   name = 'sa'
						AND is_disabled = 0 )
		BEGIN
			IF @PServer IS NULL
				OR @PServer NOT IN ( 'GPServer' )
				BEGIN
	
	/*********************************************************************************************
	PURPOSE:	Purpose of this object is to generate a random string of given length
	----------------------------------------------------------------------------------------------
	Comments:	Everything is self-explanatory.  Right now max length is set to 100. So anything
		between 1 and 100 will work for a length.

		If you specify a @charactersToUse, the bit flags get ignored.

		All spaces are stripped from the @charactersToUse.

		Characters can repeat. Will be handled in a future version.
	----------------------------------------------------------------------------------------------
	REVISION HISTORY:
	Date			Developer Name			Change Description	
	----------		--------------			------------------
	05/16/2005		Raymond Lewallen		Original Version
	05/14/2012		James N. Rzepka			Pulled from 'http://codebetter.com/raymondlewallen/2005/05/17/updated-random-password-or-string-generator-in-t-sql-for-sql-server/'
	05/14/2012		James N. Rzepka			Updated to use special characters.
	----------------------------------------------------------------------------------------------
	***************************************************************************/
					DECLARE @useNumbers BIT = 1 ,
						@useLowerCase BIT = 1 ,
						@useUpperCase BIT = 1 ,
						@useSpecial BIT = 1 ,
						@charactersToUse AS VARCHAR(100) = NULL ,
						@StringLength AS SMALLINT = 100 ,
						@String VARCHAR(100);


					SET NOCOUNT ON;

					IF @StringLength <= 0
						RAISERROR('Cannot generate a random string of zero length.',16,1);

					DECLARE @characters VARCHAR(100);
					DECLARE @count INT;

					SET @characters = '';

					IF @useSpecial = 1
						BEGIN
		-- load up special characters
		--set @count = 32
		--while @count <=47
		--begin
		--	set @characters = @characters + Cast(CHAR(@count) as char(1))
		--	set @count = @count + 1
		--end
							SET @characters = @characters + ' !#$%&()*+,-./@\^_`~';
						END;

					IF @useNumbers = 1
						BEGIN
		-- load up numbers 0 - 9
							SET @count = 48;
							WHILE @count <= 57
								BEGIN
									SET @characters = @characters
										+ CAST(CHAR(@count) AS CHAR(1));
									SET @count = @count + 1;
								END;
						END;

					IF @useUpperCase = 1
						BEGIN
		-- load up uppercase letters A - Z
							SET @count = 65;
							WHILE @count <= 90
								BEGIN
									SET @characters = @characters
										+ CAST(CHAR(@count) AS CHAR(1));
									SET @count = @count + 1;
								END;
						END;

					IF @useLowerCase = 1
						BEGIN
		-- load up lowercase letters a - z
							SET @count = 97;
							WHILE @count <= 122
								BEGIN
									SET @characters = @characters
										+ CAST(CHAR(@count) AS CHAR(1));
									SET @count = @count + 1;
								END;
						END;

					SET @count = 0;
					SET @String = '';

	-- If you specify a character set to use, the bit flags get ignored.
					IF LEN(@charactersToUse) > 0
						BEGIN
							WHILE CHARINDEX(@charactersToUse, ' ') > 0
								BEGIN
									SET @charactersToUse = REPLACE(@charactersToUse,
																  ' ', '');
								END;

							IF LEN(@charactersToUse) = 0
								RAISERROR('Cannot use an empty character set.',16,1);

							WHILE @count <= @StringLength
								BEGIN
    
									SET @String = @String
										+ SUBSTRING(@charactersToUse,
													CAST(ABS(CHECKSUM(NEWID()))
													* RAND(@count) AS INT)
													% LEN(@charactersToUse) + 1, 1);
									SET @count = @count + 1;
								END;
						END;
					ELSE
						BEGIN
							WHILE @count <= @StringLength
								BEGIN
    
									SET @String = @String + SUBSTRING(@characters,
																  CAST(ABS(CHECKSUM(NEWID()))
																  * RAND(@count) AS INT)
																  % LEN(@characters)
																  + 1, 1);
									SET @count = @count + 1;
								END;
						END;

					SET @Password = @String;

					SELECT  @SQL = '
			--Servername: ' + @@servername + '
			--PServer: ' + ISNULL(@PServer, '') + '
			USE [master]
			ALTER LOGIN [sa] WITH PASSWORD=''' + REPLACE(@Password, '''', '''''')
							+ '''
			ALTER LOGIN [sa] DISABLE
			';

			--PRINT @SQL
					EXEC (@SQL);
				END;
			ELSE
				PRINT '
			Servername: ' + @@servername + '
			PServer: ' + ISNULL(@PServer, '') + '
			No disable
			';
		END;

-- 21. Create procs and table for restart check/history PROD ONLY!!!
	--find and replace <listOfRecipients> and <listOfCopyRecipients>

	USE master;
	GO

	CREATE TABLE [dbo].[Restart_History]
		(
		  [SnapshotID] [INT] IDENTITY(1, 1)
							 NOT NULL ,
		  [ActiveNode] [VARCHAR](64) NULL ,
		  [LastRestart] [DATETIME] NULL
		)
	ON  [PRIMARY];

	GO


	CREATE PROCEDURE [dbo].[usp_restartcheck]
	/*********************************************************************************************
	PURPOSE:	The purpose of this object is to notify the DBA team when SQL starts up to assist 
	with quicker notification on failovers/reboots.
	----------------------------------------------------------------------------------------------
	REVISION HISTORY:
	Date					Developer Name					Change Description	
	----------				--------------					------------------
	09/23/2011				James N. Rzepka					Original Version
	04/09/2016				Jared Karney					Moved to master
	----------------------------------------------------------------------------------------------
	USAGE:		EXEC dbo.usp_restartcheck
	**********************************************************************************************/
	AS
		BEGIN
			SET NOCOUNT ON;

			DECLARE @Profile VARCHAR(64) ,
				@subject VARCHAR(128) ,
				@body VARCHAR(512);
			DECLARE @LastStarup DATETIME ,
				@CurrentStartup DATETIME;
			SELECT TOP 1
					@LastStarup = LastRestart
			FROM    dbo.Restart_History
			ORDER BY SnapshotID DESC;
			SELECT  @CurrentStartup = create_date
			FROM    sys.databases
			WHERE   name = 'tempdb';
			IF ISNULL(@LastStarup, '1/1/1900') <> @CurrentStartup
				BEGIN
					SELECT  @Profile = ( SELECT ISNULL(( SELECT TOP 1
																name
														 FROM   msdb.dbo.sysmail_profile
														 WHERE  name LIKE '%'
																+ ( SELECT
																  CONVERT(VARCHAR(64), SERVERPROPERTY('MachineName'))
																  ) + '%'
														 ORDER BY profile_id DESC
													   ),
													   ( SELECT TOP 1
																name
														 FROM   msdb.dbo.sysmail_profile
														 ORDER BY profile_id DESC
													   ))
									   );
					IF ISNULL(( SELECT TOP 1
										ActiveNode
								FROM    Restart_History
								ORDER BY SnapshotID DESC
							  ),
							  CONVERT(VARCHAR(64), SERVERPROPERTY('ComputerNamePhysicalNetBIOS'))) <> CONVERT(VARCHAR(64), SERVERPROPERTY('ComputerNamePhysicalNetBIOS'))
						SELECT  @subject = ( SELECT ( SELECT    CONVERT(VARCHAR(64), SERVERPROPERTY('MachineName'))
													) + ' failed over'
										   ) ,
								@body = ( SELECT    ( SELECT    CONVERT(VARCHAR(64), SERVERPROPERTY('MachineName'))
													) + ' failed over' + ' from '
													+ ( SELECT TOP 1
																ActiveNode
														FROM    Restart_History
														ORDER BY SnapshotID DESC
													  ) + ' to '
													+ CONVERT(VARCHAR(64), SERVERPROPERTY('ComputerNamePhysicalNetBIOS'))
													+ ' on '
													+ CONVERT(VARCHAR(20), @CurrentStartup, 100)
													+ '.'
										);
					ELSE
						SELECT  @subject = ( SELECT ( SELECT    CONVERT(VARCHAR(64), SERVERPROPERTY('MachineName'))
													) + ' restarted'
										   ) ,
								@body = ( SELECT    ( SELECT    CONVERT(VARCHAR(64), SERVERPROPERTY('MachineName'))
													) + ' restarted on '
													+ CONVERT(VARCHAR(20), @CurrentStartup, 100)
													+ '.'
										);
					IF SERVERPROPERTY('ComputerNamePhysicalNetBIOS') <> SERVERPROPERTY('MachineName')
						SELECT  @body = @body + CHAR(10) + 'Old Node: '
								+ ( SELECT TOP 1
											ActiveNode
									FROM    Restart_History
									ORDER BY SnapshotID DESC
								  ) + CHAR(10) + 'New Node: '
								+ ( SELECT  CONVERT(VARCHAR(64), SERVERPROPERTY('ComputerNamePhysicalNetBIOS'))
								  );
	
					SELECT  @body = @body + CHAR(10) + CHAR(10)
							+ 'Please notify the primary on-call DBA to verify the server.';
		--Page the team.
					EXEC msdb.dbo.sp_send_dbmail @profile_name = @Profile,
						@recipients = '<listOfRecipients>',
						@copy_recipients = '<listOfCopyRecipients>',
						@subject = @subject, @body = @body, @importance = 'High';

					INSERT  INTO Restart_History
							( ActiveNode ,
							  LastRestart
							)
							SELECT  CONVERT(VARCHAR(64), SERVERPROPERTY('ComputerNamePhysicalNetBIOS')) ,
									@CurrentStartup;
	
				END;

			SET NOCOUNT OFF;
		END;
	GO


	CREATE PROCEDURE dbo.usp_Startup
	/*********************************************************************************************
	PURPOSE:	The urpose of this object is to run startup stored procedures that use link 
	servers.
	----------------------------------------------------------------------------------------------
	REVISION HISTORY:
	Date					Developer Name					Change Description	
	----------				--------------					------------------
	09/23/2011				Jared Karney					Original Version
	----------------------------------------------------------------------------------------------
	USAGE:		EXEC dbo.usp_Startup
	**********************************************************************************************/
	AS
		BEGIN
			SET ANSI_NULLS ON;
			SET ANSI_WARNINGS ON;
			EXEC dbo.usp_restartcheck;
		END;
	GO

	EXEC master..sp_procoption @ProcName = 'usp_Startup', @OptionName = 'startup',
		@OptionValue = 'true'; 

	GO

	DECLARE @LastStarup DATETIME ,
		@CurrentStartup DATETIME;
	SELECT TOP 1
			@LastStarup = LastRestart
	FROM    dbo.Restart_History
	ORDER BY RestartHistoryID DESC;
	SELECT  @CurrentStartup = create_date
	FROM    sys.databases
	WHERE   name = 'tempdb';
	IF ISNULL(@LastStarup, '1/1/1900') <> @CurrentStartup
		INSERT  INTO dbo.Restart_History
				( ActiveNode ,
				  LastRestart
				)
				SELECT  CONVERT(VARCHAR(64), SERVERPROPERTY('ComputerNamePhysicalNetBIOS')) ,
						@CurrentStartup;
	GO




 












