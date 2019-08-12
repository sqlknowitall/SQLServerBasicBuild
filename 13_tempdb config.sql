/*
This script is only needed if you are running a version before 2016 and/or have not
configured your tempdb files accordingly
*/

--Check the number of CPUs
select cpu_count from sys.dm_os_sys_info

--Move tempdb and set the number of files = number of logical cores
--If more than 8 logical cores, start with 8 files
--****** MAKE SURE TO ADJUST FILE SIZES ******
USE [master]
GO
ALTER DATABASE tempdb MODIFY FILE ( NAME = 'tempdev', FILENAME = N'T:\Data\tempdb.mdf', SIZE = 8192MB , FILEGROWTH = 256MB )
GO
ALTER DATABASE tempdb MODIFY FILE ( NAME = 'templog', FILENAME = N'T:\Log\templog.ldf', SIZE = 5120MB , FILEGROWTH = 512MB )
GO
--add additional data files
ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev2', FILENAME = N'T:\DATA\tempdb2.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB )
GO
ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev3', FILENAME = N'T:\DATA\tempdb3.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB )
GO
ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev4', FILENAME = N'T:\DATA\tempdb4.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB )
GO
ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev5', FILENAME = N'T:\DATA\tempdb5.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB )
GO
ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev6', FILENAME = N'T:\DATA\tempdb6.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB )
GO
ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev7', FILENAME = N'T:\DATA\tempdb7.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB )
GO
ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev8', FILENAME = N'T:\DATA\tempdb8.ndf' , SIZE = 8192MB , FILEGROWTH = 256MB )
GO
