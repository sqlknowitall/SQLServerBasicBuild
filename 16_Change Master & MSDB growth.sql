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
PRINT (@string);
EXEC (@string);

--msdb
SET @file = ( SELECT    name
              FROM      master.sys.master_files
              WHERE     file_id = 1
                        AND DB_NAME(database_id) = 'msdb'
            );

SET @string = 'alter database [msdb] modify file (name=' + @file
    + ', maxsize=unlimited, filegrowth=1024MB);';
PRINT (@string);
EXEC (@string);


