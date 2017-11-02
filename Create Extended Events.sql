DECLARE @file1 NVARCHAR(128)
DECLARE @SQL NVARCHAR(MAX)

IF @@MICROSOFTVERSION / 0x01000000 > 10
BEGIN
		SET @file1 = N'M:\XEs\Data_Log_FileGrowth.xel'--(SELECT SUBSTRING(f.physical_name, 1, PATINDEX('%\Log\DBA_Rep_Log.ldf', f.physical_name)) + N'Data_Log_FileGrowth.xel'
		--FROM master.sys.master_files f
		--JOIN master.sys.databases d
		--ON f.database_id = d.database_id
		--WHERE d.name = 'DBA_Rep' and file_id = 2);

		SET @SQL = 
		'
		IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name=''Data_Log_FileGrowth'')
		DROP EVENT SESSION Data_Log_FileGrowth ON SERVER

		IF NOT EXISTS (SELECT * FROM sys.server_event_sessions WHERE name=''Data_Log_FileGrowth'')
		BEGIN
			CREATE EVENT SESSION [Data_Log_FileGrowth] ON SERVER 
			ADD EVENT sqlserver.database_file_size_change(
				ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.is_system,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.sql_text,sqlserver.username)),
			ADD EVENT sqlserver.databases_log_file_size_changed(
				ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.is_system,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.sql_text,sqlserver.username)) 
			ADD TARGET package0.event_file(SET filename=N''' + @file1 + ''')
			WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=ON);

			ALTER EVENT SESSION Data_Log_FileGrowth ON SERVER STATE = START;
		END;'
		--PRINT @SQL
		EXEC sp_executesql @SQL;
END
ELSE IF @@MICROSOFTVERSION / 0x01000000 = 10
BEGIN

	
		SET @file1 = N'M:\XEs\Data_Log_FileGrowth.xel'--(SELECT SUBSTRING(f.physical_name, 1, PATINDEX('%\Log\DBA_Rep_Log.ldf', f.physical_name)) + N'Data_Log_FileGrowth.xel'
		--FROM master.sys.master_files f
		--JOIN master.sys.databases d
		--ON f.database_id = d.database_id
		--WHERE d.name = 'DBA_Rep' and file_id = 2);

		SET @SQL = 
		'
		IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name=''Data_Log_FileGrowth'')
		DROP EVENT SESSION Data_Log_FileGrowth ON SERVER

		IF NOT EXISTS (SELECT * FROM sys.server_event_sessions WHERE name=''Data_Log_FileGrowth'')
		BEGIN
			CREATE EVENT SESSION [Data_Log_FileGrowth] ON SERVER 
			ADD EVENT sqlserver.databases_data_file_size_changed(
				ACTION(sqlserver.sql_text						--	1
							,sqlserver.database_id					--	2
							,sqlserver.client_app_name				--	3
							,sqlserver.client_hostname				--	4
							,sqlserver.session_nt_username			--	5
							,sqlserver.username						--	6
							,sqlserver.is_system					--	7
							,sqlserver.session_id)	--8
				),
			ADD EVENT sqlserver.databases_log_file_size_changed(
				ACTION(sqlserver.sql_text						--	1
							,sqlserver.database_id					--	2
							,sqlserver.client_app_name				--	3
							,sqlserver.client_hostname				--	4
							,sqlserver.session_nt_username			--	5
							,sqlserver.username						--	6
							,sqlserver.is_system					--	7
							,sqlserver.session_id)	--8
				)
			ADD TARGET package0.asynchronous_file_target(SET filename = N''' + @file1 + ''', metadatafile = N''' + REPLACE(@file1, '.xel', '.xem') + ''')
			WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=ON);

			ALTER EVENT SESSION Data_Log_FileGrowth ON SERVER STATE = START;
		END;
		'
		--PRINT @SQL
		EXEC sp_executesql @SQL;
END


--DECLARE @file1 NVARCHAR(128)
--DECLARE @SQL NVARCHAR(MAX)

IF @@MICROSOFTVERSION / 0x01000000 > 10
BEGIN

	SET @file1 = N'M:\XEs\what_queries_are_failing.xel'--(SELECT SUBSTRING(f.physical_name, 1, PATINDEX('%\Log\DBA_Rep_Log.ldf', f.physical_name)) + N'what_queries_are_failing.xel'
		--FROM master.sys.master_files f
		--JOIN master.sys.databases d
		--ON f.database_id = d.database_id
		--WHERE d.name = 'DBA_Rep' and file_id = 2);

		SET @SQL = 
		'
		IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name=''what_queries_are_failing'')
		DROP EVENT SESSION what_queries_are_failing ON SERVER

		IF NOT EXISTS (SELECT * FROM sys.server_event_sessions WHERE name=''what_queries_are_failing'')
		BEGIN
			CREATE EVENT SESSION [what_queries_are_failing] ON SERVER 
			ADD EVENT sqlserver.error_reported(
				ACTION(sqlserver.sql_text							--	1
							,sqlserver.tsql_stack					--	2
							,sqlserver.database_id					--	3
							,sqlserver.username) 					--	4
							WHERE ([severity]> 10) )
			ADD TARGET package0.asynchronous_file_target(SET filename=N''' + @file1 + ''')
			WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF);

			--ALTER EVENT SESSION what_queries_are_failing ON SERVER STATE = START;
		END;
		'
		--PRINT @SQL
		EXEC sp_executesql @SQL;
END
ELSE IF @@MICROSOFTVERSION / 0x01000000 = 10
BEGIN

	SET @file1 = N'M:\XEs\what_queries_are_failing.xel'--(SELECT SUBSTRING(f.physical_name, 1, PATINDEX('%\Log\DBA_Rep_Log.ldf', f.physical_name)) + N'what_queries_are_failing.xel'
		--FROM master.sys.master_files f
		--JOIN master.sys.databases d
		--ON f.database_id = d.database_id
		--WHERE d.name = 'DBA_Rep' and file_id = 2);

		SET @SQL = 
		'
		IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name=''what_queries_are_failing'')
		DROP EVENT SESSION what_queries_are_failing ON SERVER

		IF NOT EXISTS (SELECT * FROM sys.server_event_sessions WHERE name=''what_queries_are_failing'')
		BEGIN
			CREATE EVENT SESSION [what_queries_are_failing] ON SERVER 
			ADD EVENT sqlserver.error_reported(
				ACTION(sqlserver.sql_text							--	1
							,sqlserver.tsql_stack					--	2
							,sqlserver.database_id					--	3
							,sqlserver.username) 					--	4
							WHERE ([severity]> 10) )
			ADD TARGET package0.asynchronous_file_target(SET filename = N''' + @file1 + ''', metadatafile = N''' + REPLACE(@file1, '.xel', '.xem') + ''')
			WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF);

			--ALTER EVENT SESSION what_queries_are_failing ON SERVER STATE = START;
		END;
		'
		--PRINT @SQL
		EXEC sp_executesql @SQL;
END

