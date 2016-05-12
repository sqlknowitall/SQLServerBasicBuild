--If not doing a side-by-side where xp_cmdshell is already enabled on the source server...
EXEC sys.sp_configure 'Advanced Options', 1
RECONFIGURE WITH OVERRIDE
EXEC sys.sp_configure 'xp_cmdshell', 0
RECONFIGURE WITH OVERRIDE

