USE msdb
GO

CREATE TABLE dbo.SQLJobActivationHistory(
	EventRowID BIGINT IDENTITY(1,1) NOT NULL,
	EventTime DATETIME NULL,
	HostName NVARCHAR(256) NULL,
	Instance NVARCHAR(256) NULL,
	JobName NVARCHAR(256) NULL,
	[Enabled] BIT NULL,
	[Message] NVARCHAR(256) NULL,
	AuditUser NVARCHAR(256) NULL,
	SessionLoginName NVARCHAR(256) NULL,
	AuditDate SMALLDATETIME NOT NULL,
 CONSTRAINT PK_SQLJobActivationHistory_EventRowID PRIMARY KEY NONCLUSTERED 
(
	EventRowID ASC
));

CREATE TABLE dbo.SQLJobModificationHistory(
	EventRowID BIGINT IDENTITY(1,1) NOT NULL,
	EventTime DATETIME NULL,
	EventType VARCHAR(128) NULL,
	HostName VARCHAR(128) NULL,
	Instance VARCHAR(128) NULL,
	JobID VARCHAR(256) NULL,
	JobName VARCHAR(256) NULL,
	OldJobName VARCHAR(256) NULL,
	JobCreationDate DATETIME NOT NULL,
	JobModificationDate DATETIME NOT NULL,
	AuditUser VARCHAR(128) NULL,
	SessionLoginName VARCHAR(256) NULL,
	AuditDate SMALLDATETIME NOT NULL,
 CONSTRAINT PK_SQLJobModificationHistory_EventRowID PRIMARY KEY NONCLUSTERED 
(
	EventRowID ASC
))

ALTER TABLE [dbo].[SQLJobActivationHistory] ADD  CONSTRAINT [DF_SQLJobActivationHistory_SessionLoginName]  DEFAULT (ORIGINAL_LOGIN()) FOR [SessionLoginName]

ALTER TABLE [dbo].[SQLJobActivationHistory] ADD  CONSTRAINT [DF_SQLJobActivationHistory_AuditDate]  DEFAULT (GETDATE()) FOR [AuditDate]

ALTER TABLE [dbo].[SQLJobModificationHistory] ADD  CONSTRAINT [DF_SQLJobModificationHistory_SessionLoginName]  DEFAULT (ORIGINAL_LOGIN()) FOR [SessionLoginName]

ALTER TABLE [dbo].[SQLJobModificationHistory] ADD  CONSTRAINT [DF_SQLJobModificationHistory_AuditDate]  DEFAULT (GETDATE()) FOR [AuditDate]
GO

 CREATE TRIGGER [dbo].[AuditDeletedSQLAgentJobTrigger]
 ON [msdb].[dbo].[sysjobs] 
 FOR DELETE 
 /*
 * Stored Procedure: [AuditDeletedSQLAgentJobTrigger] **
 * Version #: v1.0.0 **
 * **
 * Purpose/Comments **
 * ================ **
 * Trigger to monitor all deletion events of SQL Agent jobs. **
 ** * **
 */ AS BEGIN 
 
BEGIN TRY
 
BEGIN TRANSACTION
 SET NOCOUNT ON 
 
DECLARE 
 @UserName [varchar](256)
 ,@SessionLogin [varchar](128) 
 ,@HostName [varchar](128)
 ,@JobID [varchar](256) 
 ,@JobName [varchar](256) 
 ,@SQLInstance [varchar](128)
 ,@DateJobCreated [datetime] 
 ,@DateJobModified [datetime]
 
SELECT @UserName = SYSTEM_USER
 SELECT @SessionLogin = ORIGINAL_LOGIN()
 SELECT @HostName = HOST_NAME() 
 SELECT @JobID = [job_id] FROM Deleted 
 SELECT @JobName = [name] FROM Deleted
 SELECT @SQLInstance = CONVERT([varchar](128), SERVERPROPERTY('ServerName'))
 SELECT @DateJobCreated = [date_created] FROM Deleted
 SELECT @DateJobModified = [date_modified] FROM Deleted
 
IF(SELECT COUNT([name]) FROM [master].[dbo].[sysdatabases] 
 WHERE [name] IN ('msdb') 
 AND [status]&32 <> 32 AND [status]&256 <> 256 
 AND [status]&32768 <> 32768 
 AND DATABASEPROPERTYEX([name],'Status') NOT IN ( 'OFFLINE'
 ,'RESTORING'
 ,'RECOVERING'
 ,'SUSPECT') ) = 1 
 BEGIN
 INSERT INTO msdb.[dbo].[SQLJobModificationHistory]
 ([EventTime]
 ,[EventType]
 ,[HostName]
 ,[Instance]
 ,[JobID]
 ,[JobName]
 ,[OldJobName]
 ,[JobCreationDate]
 ,[JobModificationDate]
 ,[AuditUser]
 ,[SessionLoginName])
 VALUES 
 (GETDATE()
 ,'JOB_DELETED'
 ,@HostName
 ,@SQLInstance
 ,@JobID
 ,@JobName
 ,'-- Not Applicable --'
 ,@DateJobCreated
 ,@DateJobModified
 ,@UserName
 ,@SessionLogin)
 END
 COMMIT TRANSACTION;
 END TRY 
 
BEGIN CATCH 
 -- Test whether the transaction is uncommittable.
 IF (XACT_STATE()) = -1
 BEGIN
 PRINT
 N'The transaction is in an uncommittable state. ' +
 'Rolling back transaction.'
 ROLLBACK TRANSACTION;
 END;
 -- Test whether the transaction is active and valid.
 IF (XACT_STATE()) = 1
 BEGIN
 PRINT
 N'The transaction is committable. ' +
 'Committing transaction.'
 COMMIT TRANSACTION; 
 END;
 
DECLARE @ErrorMessage [nvarchar](4000);
 DECLARE @ErrorSeverity [int];
 DECLARE @ErrorState [int];
 
SELECT 
 @ErrorMessage = ERROR_MESSAGE(),
 @ErrorSeverity = ERROR_SEVERITY(),
 @ErrorState = ERROR_STATE();
 
-- RAISERROR inside the CATCH block to return error
 -- information about the original error that caused
 -- execution to jump to the CATCH block.
 RAISERROR (@ErrorMessage, -- Message text.
 @ErrorSeverity, -- Severity.
 @ErrorState ); -- State.
 END CATCH 
 END

GO

 CREATE TRIGGER [dbo].[AuditModifiedSQLAgentJobTrigger]
 ON [msdb].[dbo].[sysjobs] 
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
 AS BEGIN 
 
BEGIN TRY
 
BEGIN TRANSACTION
 SET NOCOUNT ON 
 DECLARE 
 @UserName [varchar](256)
 ,@SessionLogin [varchar](128) 
 ,@HostName [varchar](128)
 ,@JobID [varchar](256) 
 ,@JobName [varchar](256) 
 ,@OldJobName [varchar](256)
 ,@SQLInstance [varchar](128)
 ,@DateJobCreated [datetime] 
 ,@DateJobModified [datetime]
 
SELECT @UserName = SYSTEM_USER
 SELECT @SessionLogin = ORIGINAL_LOGIN()
 SELECT @HostName = HOST_NAME() 
 SELECT @JobID = [job_id] FROM Inserted 
 SELECT @JobName = [name] FROM Inserted 
 SELECT @OldJobName = [name] FROM Deleted
 SELECT @SQLInstance = CONVERT([varchar](128), SERVERPROPERTY('ServerName'))
 SELECT @DateJobCreated = [date_created] FROM Inserted
 SELECT @DateJobModified = [date_modified] FROM Inserted
 IF(SELECT COUNT([name]) FROM [master].[dbo].[sysdatabases] 
 WHERE [name] IN ('msdb') 
 AND [status]&32 <> 32 AND [status]&256 <> 256 
 AND [status]&32768 <> 32768 
 AND DATABASEPROPERTYEX([name],'Status') NOT IN ( 'OFFLINE'
 ,'RESTORING'
 ,'RECOVERING'
 ,'SUSPECT') ) = 1 
 BEGIN
 INSERT INTO msdb.[dbo].[SQLJobModificationHistory]
 ([EventTime]
 ,[EventType]
 ,[HostName]
 ,[Instance]
 ,[JobID]
 ,[JobName]
 ,[OldJobName]
 ,[JobCreationDate]
 ,[JobModificationDate]
 ,[AuditUser]
 ,[SessionLoginName])
 VALUES 
 (GETDATE()
 ,'JOB_MODIFIED'
 ,@HostName
 ,@SQLInstance
 ,@JobID
 ,@JobName
 ,@OldJobName
 ,@DateJobCreated
 ,@DateJobModified
 ,@UserName
 ,@SessionLogin)
 END
 COMMIT TRANSACTION;
 END TRY 
 
BEGIN CATCH 
 -- Test whether the transaction is uncommittable.
 IF (XACT_STATE()) = -1
 BEGIN
 PRINT
 N'The transaction is in an uncommittable state. ' +
 'Rolling back transaction.'
 ROLLBACK TRANSACTION;
 END;
 -- Test whether the transaction is active and valid.
 IF (XACT_STATE()) = 1
 BEGIN
 PRINT
 N'The transaction is committable. ' +
 'Committing transaction.'
 COMMIT TRANSACTION; 
 END;
 
DECLARE @ErrorMessage [nvarchar](4000);
 DECLARE @ErrorSeverity [int];
 DECLARE @ErrorState [int];
 
SELECT 
 @ErrorMessage = ERROR_MESSAGE(),
 @ErrorSeverity = ERROR_SEVERITY(),
 @ErrorState = ERROR_STATE();
 
-- RAISERROR inside the CATCH block to return error
 -- information about the original error that caused
 -- execution to jump to the CATCH block.
 RAISERROR (@ErrorMessage, -- Message text.
 @ErrorSeverity, -- Severity.
 @ErrorState ); -- State.
 END CATCH 
 END

GO

/****** Object:  Trigger [dbo].[AuditNewSQLAgentJobTrigger]    Script Date: 12/22/2015 1:52:03 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

 CREATE TRIGGER [dbo].[AuditNewSQLAgentJobTrigger]
 ON [msdb].[dbo].[sysjobs] 
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
 AS BEGIN 
 
BEGIN TRY
 
BEGIN TRANSACTION
 SET NOCOUNT ON 
 DECLARE 
 @UserName [varchar](256)
 ,@SessionLogin [varchar](128) 
 ,@HostName [varchar](128)
 ,@JobID [varchar](256) 
 ,@JobName [varchar](256) 
 ,@OldJobName [varchar](256)
 ,@SQLInstance [varchar](128)
 ,@DateJobCreated [datetime] 
 ,@DateJobModified [datetime]
 
SELECT @UserName = SYSTEM_USER
 SELECT @SessionLogin = ORIGINAL_LOGIN()
 SELECT @HostName = HOST_NAME() 
 SELECT @JobID = [job_id] FROM Inserted 
 SELECT @JobName = [name] FROM Inserted 
 SELECT @OldJobName = [name] FROM Deleted
 SELECT @SQLInstance = CONVERT([varchar](128), SERVERPROPERTY('ServerName'))
 SELECT @DateJobCreated = [date_created] FROM Inserted
 SELECT @DateJobModified = [date_modified] FROM Inserted
 IF(SELECT COUNT([name]) FROM [master].[dbo].[sysdatabases] 
 WHERE [name] IN ('msdb') 
 AND [status]&32 <> 32 AND [status]&256 <> 256 
 AND [status]&32768 <> 32768 
 AND DATABASEPROPERTYEX([name],'Status') NOT IN ( 'OFFLINE'
 ,'RESTORING'
 ,'RECOVERING'
 ,'SUSPECT') ) = 1 
 BEGIN
 INSERT INTO msdb.[dbo].[SQLJobModificationHistory]
 ([EventTime]
 ,[EventType]
 ,[HostName]
 ,[Instance]
 ,[JobID]
 ,[JobName]
 ,[OldJobName]
 ,[JobCreationDate]
 ,[JobModificationDate]
 ,[AuditUser]
 ,[SessionLoginName])
 VALUES 
 (GETDATE()
 ,'JOB_CREATED'
 ,@HostName
 ,@SQLInstance
 ,@JobID
 ,@JobName
 ,@OldJobName
 ,@DateJobCreated
 ,@DateJobModified
 ,@UserName
 ,@SessionLogin)
 END
 COMMIT TRANSACTION;
 END TRY 
 
BEGIN CATCH 
 -- Test whether the transaction is uncommittable.
 IF (XACT_STATE()) = -1
 BEGIN
 PRINT
 N'The transaction is in an uncommittable state. ' +
 'Rolling back transaction.'
 ROLLBACK TRANSACTION;
 END;
 -- Test whether the transaction is active and valid.
 IF (XACT_STATE()) = 1
 BEGIN
 PRINT
 N'The transaction is committable. ' +
 'Committing transaction.'
 COMMIT TRANSACTION; 
 END;
 
DECLARE @ErrorMessage [nvarchar](4000);
 DECLARE @ErrorSeverity [int];
 DECLARE @ErrorState [int];
 
SELECT 
 @ErrorMessage = ERROR_MESSAGE(),
 @ErrorSeverity = ERROR_SEVERITY(),
 @ErrorState = ERROR_STATE();
 
-- RAISERROR inside the CATCH block to return error
 -- information about the original error that caused
 -- execution to jump to the CATCH block.
 RAISERROR (@ErrorMessage, -- Message text.
 @ErrorSeverity, -- Severity.
 @ErrorState ); -- State.
 END CATCH 
 END

GO

/****** Object:  Trigger [dbo].[AuditSQLAgentJobActivationTrigger]    Script Date: 12/22/2015 1:52:03 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

 CREATE TRIGGER [dbo].[AuditSQLAgentJobActivationTrigger] 
 ON [msdb].[dbo].[sysjobs] 
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
 AS BEGIN 
 
BEGIN TRY
 
BEGIN TRANSACTION
 SET NOCOUNT ON 
 DECLARE 
 @UserName [varchar](256)
 ,@SessionLogin [varchar](128) 
 ,@HostName [varchar](128) 
 ,@JobName [varchar](256) 
 ,@SQLInstance [varchar](128)
 ,@NewEnabled [int] 
 ,@OldEnabled [int] 
 
SELECT @UserName = SYSTEM_USER
 SELECT @SessionLogin = ORIGINAL_LOGIN()
 SELECT @HostName = HOST_NAME() 
 SELECT @JobName = [name] FROM Inserted
 SELECT @NewEnabled = [enabled] FROM Inserted 
 SELECT @OldEnabled = [enabled] FROM Deleted 
 SELECT @SQLInstance = CONVERT([varchar](128), SERVERPROPERTY('ServerName'))
 
-- check if the enabled flag has been updated. 
 IF @NewEnabled <> @OldEnabled 
 BEGIN 
 IF(SELECT COUNT([name]) FROM [master].[dbo].[sysdatabases] 
 WHERE [name] IN ('msdb') 
 AND [status]&32 <> 32 AND [status]&256 <> 256 
 AND [status]&32768 <> 32768 
 AND DATABASEPROPERTYEX([name],'Status') NOT IN ( 'OFFLINE'
 ,'RESTORING'
 ,'RECOVERING'
 ,'SUSPECT') ) = 1 
 BEGIN
 IF @NewEnabled = 1 
 BEGIN 
 INSERT INTO msdb.[dbo].[SQLJobActivationHistory]
 ( [EventTime]
 ,[HostName]
 ,[Instance]
 ,[JobName]
 ,[Enabled]
 ,[Message]
 ,[AuditUser]
 ,[SessionLoginName] )
 VALUES 
 ( GETDATE()
 ,@HostName
 ,@SQLInstance
 ,@JobName
 ,1
 ,'Job has been enabled.'
 ,@UserName 
 ,@SessionLogin ) 
 END -- End of inner-IF block... 
 IF @NewEnabled = 0 
 BEGIN 
 INSERT INTO msdb.[dbo].[SQLJobActivationHistory]
 ([EventTime]
 ,[HostName]
 ,[Instance]
 ,[JobName]
 ,[Enabled]
 ,[Message]
 ,[AuditUser]
 ,[SessionLoginName] )
 VALUES 
 ( GETDATE()
 ,@HostName
 ,@SQLInstance
 ,@JobName
 ,0
 ,'Job has been disabled.'
 ,@UserName 
 ,@SessionLogin )
 END -- End of inner-IF block...
 END -- End of outer-IF block...
 END -- End of outer-IF block...
 COMMIT TRANSACTION;
 END TRY 
 
BEGIN CATCH 
 -- Test whether the transaction is uncommittable.
 IF (XACT_STATE()) = -1
 BEGIN
 PRINT
 N'The transaction is in an uncommittable state. ' +
 'Rolling back transaction.'
 ROLLBACK TRANSACTION;
 END;
 -- Test whether the transaction is active and valid.
 IF (XACT_STATE()) = 1
 BEGIN
 PRINT
 N'The transaction is committable. ' +
 'Committing transaction.'
 COMMIT TRANSACTION; 
 END;
 
DECLARE @ErrorMessage [NVARCHAR](4000);
 DECLARE @ErrorSeverity [INT];
 DECLARE @ErrorState [INT];
 
SELECT 
 @ErrorMessage = ERROR_MESSAGE(),
 @ErrorSeverity = ERROR_SEVERITY(),
 @ErrorState = ERROR_STATE();
 
-- RAISERROR inside the CATCH block to return error
 -- information about the original error that caused
 -- execution to jump to the CATCH block.
 RAISERROR (@ErrorMessage, -- Message text.
 @ErrorSeverity, -- Severity.
 @ErrorState ); -- State.
 END CATCH 
 END

GO




