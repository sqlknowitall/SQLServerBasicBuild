SELECT * FROM sys.dm_server_registry WHERE value_name IN ('JobHistoryMaxRows','JobHistoryMaxRowsPerJob')
EXEC msdb.dbo.sp_set_sqlagent_properties @jobhistory_max_rows = 100000, @jobhistory_max_rows_per_job = 1000
SELECT * FROM sys.dm_server_registry WHERE value_name IN ('JobHistoryMaxRows','JobHistoryMaxRowsPerJob')