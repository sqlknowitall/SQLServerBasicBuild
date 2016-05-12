USE [msdb]

-- Create the Operators
IF NOT EXISTS (
		SELECT 1
		FROM msdb.dbo.sysoperators
		WHERE NAME = 'DBAPager'
		)
BEGIN
	EXEC msdb.dbo.sp_add_operator @name = N'DBAPager'
		,@enabled = 1
		,@email_address = N'<email address for dba pager and dba team>'
END;
GO

IF NOT EXISTS (
		SELECT 1
		FROM msdb.dbo.sysoperators
		WHERE NAME = 'DBAAlerts'
		)
BEGIN
	EXEC msdb.dbo.sp_add_operator @name = N'DBAAlerts'
		,@enabled = 1
		,@email_address = N'<email address for dba team>'
END;
GO

IF NOT EXISTS (
		SELECT 1
		FROM msdb.dbo.sysoperators
		WHERE NAME = 'SQLPager'
		)
BEGIN
	EXEC msdb.dbo.sp_add_operator @name = N'SQLPager'
		,@enabled = 1
		,@email_address = N'<email addresses for dba team pager, dba team, and server team>'
END;
GO

IF NOT EXISTS (
		SELECT 1
		FROM msdb.dbo.sysoperators
		WHERE NAME = 'SQLAlerts'
		)
BEGIN
	EXEC msdb.dbo.sp_add_operator @name = N'SQLAlerts'
		,@enabled = 1
		,@email_address = N'<email addresses for dba team and server team>'
END;
GO

USE [msdb]
GO

EXEC master.dbo.sp_MSsetalertinfo @failsafeoperator=N'DBAAlerts', 
		@notificationmethod=1
GO


/***********************************************
-- Drop and recreate alerts according to Coyote standards
************************************************/
DECLARE @oldAlertName SYSNAME
DECLARE @pageOperator SYSNAME
DECLARE @seEmailOperator SYSNAME
DECLARE @sePageOperator SYSNAME
DECLARE @emailOperator SYSNAME

SET @pageOperator = 'DBAPager'
SET @emailOperator = 'DBAAlerts'
SET @sePageOperator = 'SQLPager'
SET @seEmailOperator = 'SQLAlerts'



-- Fatal Error - 823 (Hard I/O Error)
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 823
			AND severity = 0
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 823
		AND severity = 0;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - 823 (Hard I/O Error)'
	,@message_id = 823
	,@severity = 0
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N'This is where SQL Server has asked the OS to read the page but it cant'
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - 823 (Hard I/O Error)'
	,@operator_name = @seEmailOperator
	,@notification_method = 1;

-- Fatal Error - 824 (Soft I/O Error)
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 824
			AND severity = 0
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 824
		AND severity = 0;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - 824 (Soft I/O Error)'
	,@message_id = 824
	,@severity = 0
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N'This is where the OS could read the page but SQL Server decided that the page was corrupt - for example with a page checksum failure'
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - 824 (Soft I/O Error)'
	,@operator_name = @seEmailOperator
	,@notification_method = 1;

-- Fatal Error - 825 (Read/Retry I/O Error)
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 825
			AND severity = 0
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 825
		AND severity = 0;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - 825 (Read/Retry I/O Error)'
	,@message_id = 825
	,@severity = 0
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N'This is where either an 823 or 824 occured, SQL server retried the IO automatically and it succeeded. This error is written to the errorlog only - you need to be aware of these as they''re a sign of the IO subsystem going awry. There''s no way to turn off read-retry and force SQL Server to ''fail-fast.'''
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - 825 (Read/Retry I/O Error)'
	,@operator_name = @seEmailOperator
	,@notification_method = 1;

-- Fatal Error - 832 (Memory Error)
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 832
			AND severity = 0
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 832
		AND severity = 0;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - 832 (Memory Error)'
	,@message_id = 832
	,@severity = 0
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N'A page that should have been constant has changed. This usually indicates a memory failure or other hardware or OS corruption.'
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - 832 (Memory Error)'
	,@operator_name = @seEmailOperator
	,@notification_method = 1;

-- Error - 9100 (Index Corruption)
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 9100
			AND severity = 0
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 9100
		AND severity = 0;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Error - 9100 (Index Corruption)'
	,@message_id = 9100
	,@severity = 0
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N'Possible index corruption detected. Run DBCC CHECKDB.'
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Error - 9100 (Index Corruption)'
	,@operator_name = @emailOperator
	,@notification_method = 1;

-- Error - Miscellaneous User Error
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 0
			AND severity = 16
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 0
		AND severity = 16;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Error - Miscellaneous User Error'
	,@message_id = 0
	,@severity = 16
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N''
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Error - Miscellaneous User Error'
	,@operator_name = @emailOperator
	,@notification_method = 1;

-- Error - Insufficient Resources
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 0
			AND severity = 17
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 0
		AND severity = 17;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Error - Insufficient Resources'
	,@message_id = 0
	,@severity = 17
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N''
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Error - Insufficient Resources'
	,@operator_name = @emailOperator
	,@notification_method = 1;

-- Error - Internal
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 0
			AND severity = 18
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 0
		AND severity = 18;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Error - Internal'
	,@message_id = 0
	,@severity = 18
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N''
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Error - Internal'
	,@operator_name = @emailOperator
	,@notification_method = 1;

-- Fatal Error - Resource
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 0
			AND severity = 19
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 0
		AND severity = 19;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Resource'
	,@message_id = 0
	,@severity = 19
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N''
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Resource'
	,@operator_name = @emailOperator
	,@notification_method = 1;

-- Fatal Error - Current Process
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 0
			AND severity = 20
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 0
		AND severity = 20;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Current Process'
	,@message_id = 0
	,@severity = 20
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N''
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Current Process'
	,@operator_name = @emailOperator
	,@notification_method = 1;

-- Fatal Error - Database Process
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 0
			AND severity = 21
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 0
		AND severity = 21;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Database Process'
	,@message_id = 0
	,@severity = 21
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N''
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Database Process'
	,@operator_name = @emailOperator
	,@notification_method = 1;

-- Fatal Error - Table Integrity
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 0
			AND severity = 22
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 0
		AND severity = 22;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Table Integrity'
	,@message_id = 0
	,@severity = 22
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N''
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Table Integrity'
	,@operator_name = @emailOperator
	,@notification_method = 1;

-- Fatal Error - Database Integrity
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 0
			AND severity = 23
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 0
		AND severity = 23;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Database Integrity'
	,@message_id = 0
	,@severity = 23
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N''
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Database Integrity'
	,@operator_name = @pageOperator
	,@notification_method = 1;

-- Fatal Error - Hardware Error
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 0
			AND severity = 24
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 0
		AND severity = 24;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Hardware Error'
	,@message_id = 0
	,@severity = 24
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N''
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Hardware Error'
	,@operator_name = @sePageOperator
	,@notification_method = 1;

-- Fatal Error - Miscellaneous
IF EXISTS (
		SELECT 1
		FROM msdb.dbo.sysalerts
		WHERE message_id = 0
			AND severity = 25
		)
BEGIN
	SELECT @oldAlertName = NAME
	FROM msdb.dbo.sysalerts
	WHERE message_id = 0
		AND severity = 25;

	EXEC msdb.dbo.sp_delete_alert @name = @oldAlertName;
END

EXEC msdb.dbo.sp_add_alert @name = N'Fatal Error - Miscellaneous'
	,@message_id = 0
	,@severity = 25
	,@enabled = 1
	,@delay_between_responses = 600
	,@include_event_description_in = 1
	,@notification_message = N''
	,@category_name = N'[Uncategorized]'
	,@job_id = N'00000000-0000-0000-0000-000000000000';

-- Add Notification
EXEC msdb.dbo.sp_add_notification @alert_name = N'Fatal Error - Miscellaneous'
	,@operator_name = @emailOperator
	,@notification_method = 1;