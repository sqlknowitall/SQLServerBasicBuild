-- search for <company.mailserver.com> and replace it with your mail server

-- make sure to change the @TestEmailAccount to whatever account you want to
-- use as the test receiver

sp_configure 'advanced options', 1
reconfigure
GO
sp_configure 'Database Mail XPs', 1
reconfigure
GO

DECLARE @ProfileName varchar(200),
		@ProfieDescription varchar(8000),
		@ProfilePricipleID varchar(10),
		@isProfileDefault varchar(2),
		@AccountName varchar(200),
		@AccountDescription varchar(8000),
		@AccountFromEmail varchar(500),
		@AccountDisplayName varchar(500),
		@AccountReplyEmail varchar(500),
		@AccountMailServer varchar(500),
		@AccountSquenceNumber varchar(10),
		@TestEmailAccount varchar(200),
		@ShowServerInfo bit,
		@RunDBMailSETup bit,
		@RunDBMailTest bit,
		@cmd varchar(max)
		
SELECT @RunDBMailSETup  = 1,
		@RunDBMailTest = 1,
		@ShowServerInfo = 1,
		@TestEmailAccount = 'yourEmail@domain.com', --Plug in YOUR email here...do not use the team DL.
		
		@ProfileName = convert(varchar(32),convert(varchar(32),LEFT(@@servername, CASE charindex('\', @@servername) WHEN 0 THEN len(@@servername) ELSE charindex('\', @@servername) - 1 END))),
		
		
		
		@ProfieDescription = '',
		@ProfilePricipleID = '0',
		@isProfileDefault = '1',
		
		@AccountName = convert(varchar(32),LEFT(@@servername, CASE charindex('\', @@servername) WHEN 0 THEN len(@@servername) ELSE charindex('\', @@servername) - 1 END)),
		@AccountDescription = '',
		@AccountFromEmail = convert(varchar(32),LEFT(@@servername, CASE charindex('\', @@servername) WHEN 0 THEN len(@@servername) ELSE charindex('\', @@servername) - 1 END)) + '@coyote.com',
		@AccountDisplayName = convert(varchar(32),@@servername),
		@AccountReplyEmail = '',
		@AccountMailServer = '<company.mailserver.com>',
		@AccountSquenceNumber = '1'
		
IF(@RunDBMailSETup = 1)
BEGIN
	EXEC msdb.dbo.sysmail_add_profile_sp
				@profile_name = @ProfileName,
				@description = @AccountDescription

	EXEC msdb.dbo.sysmail_add_principalprofile_sp
				@profile_name = @ProfileName,
				@principal_id = @ProfilePricipleID,
				@is_default = @isProfileDefault

	EXEC msdb.dbo.sysmail_add_account_sp
				@account_name = @AccountName,
				@description = @ProfieDescription,
				@email_address = @AccountFromEmail,
				@replyto_address = @AccountReplyEmail,
				@display_name = @AccountDisplayName,
				@mailserver_name = @AccountMailServer

	EXEC msdb.dbo.sysmail_add_profileaccount_sp
				@profile_name = @ProfileName,
				@account_name = @AccountName,
				@sequence_number = @AccountSquenceNumber

	
	EXEC msdb.dbo.sp_set_sqlagent_properties @email_profile=@profilename, @databasemail_profile=@profilename,
			@email_save_in_sent_folder=1, 
			@use_databasemail=1

END

IF(@ShowServerInfo = 1)
BEGIN
	SELECT 'Profile Info', *
	FROM msdb.dbo.sysmail_profile p
	LEFT JOIN msdb.dbo.sysmail_principalprofile pp
	ON p.profile_id = pp.profile_id

	SELECT 'Server info', * FROM msdb.dbo.sysmail_account a
	LEFT JOIN msdb.dbo.sysmail_server s
	ON a.account_id = s.account_id

	SELECT 'Profile + Account Info', p.*, a.*
	FROM msdb.dbo.sysmail_profile p
	JOIN msdb.dbo.sysmail_profileaccount pa
	ON p.profile_id = pa.profile_id
	JOIN msdb.dbo.sysmail_account a
	ON pa.account_id = a.account_id
END



IF(@RunDBMailTest = 1)
BEGIN
	DECLARE @Body nvarchar(max)
	SELECT @Body = 'This is a test e-mail sent from Database Mail on ' + @@SERVERNAME + '.'
	EXEC msdb.dbo.sp_send_dbmail
				@profile_name = @ProfileName,
				@recipients = @TestEmailAccount,
				@subject = 'Database Mail Test',
				@body = @Body
END


