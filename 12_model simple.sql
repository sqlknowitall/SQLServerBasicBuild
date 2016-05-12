USE [master]
GO
ALTER DATABASE [model] SET RECOVERY SIMPLE
GO
SELECT recovery_model_desc
FROM sys.databases
WHERE DB_NAME(database_id) = 'model'