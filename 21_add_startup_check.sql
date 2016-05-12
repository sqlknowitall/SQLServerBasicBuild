--find and replace <listOfRecipients> and <listOfCopyRecipients>

USE master
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
END
GO


CREATE procedure dbo.usp_Startup
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
set ANSI_NULLS ON
SET ANSI_WARNINGS ON
exec dbo.usp_restartcheck
END
GO

EXEC master..sp_procoption 
	  @ProcName = 'usp_Startup' 
	, @OptionName =  'startup' 
	, @OptionValue =  'true' 

GO

DECLARE @LastStarup datetime, @CurrentStartup datetime
SELECT TOP 1 @LastStarup = LastRestart FROM dbo.Restart_History order by RestartHistoryID DESC
SELECT @CurrentStartup = create_date from sys.databases where name = 'tempdb'
IF isnull(@LastStarup, '1/1/1900') <> @CurrentStartup
	INSERT INTO dbo.Restart_History (ActiveNode, LastRestart)
	SELECT convert(varchar(64),SERVERPROPERTY('ComputerNamePhysicalNetBIOS')), @CurrentStartup
GO
