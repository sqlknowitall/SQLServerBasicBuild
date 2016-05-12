/* 
   This will recommend a MAXDOP setting appropriate for your machine's NUMA memory
   configuration.  You will need to evaluate this setting in a non-production 
   environment before moving it to production.

   MAXDOP can be configured using:  
   EXEC sp_configure 'max degree of parallelism',X;
   RECONFIGURE

   If this instance is hosting a Sharepoint database, you MUST specify MAXDOP=1 
   (URL wrapped for readability)
   http://blogs.msdn.com/b/rcormier/archive/2012/10/25/
   you-shall-configure-your-maxdop-when-using-sharepoint-2013.aspx

   Biztalk (all versions, including 2010): 
   MAXDOP = 1 is only required on the BizTalk Message Box
   database server(s), and must not be changed; all other servers hosting other 
   BizTalk Server databases may return this value to 0 if set.
   http://support.microsoft.com/kb/899000
*/


DECLARE @CoreCount int;
DECLARE @NumaNodes int;

SET @CoreCount = (SELECT i.cpu_count from sys.dm_os_sys_info i);
SET @NumaNodes = (
    SELECT MAX(c.memory_node_id) + 1 
    FROM sys.dm_os_memory_clerks c 
    WHERE memory_node_id < 64
    );

IF @CoreCount > 4 /* If less than 5 cores, don't bother. */
BEGIN
    DECLARE @MaxDOP int;

    --@CoreCount / @NumaNodes
    SET @MaxDOP = @CoreCount / @NumaNodes; 


    /* Cap MAXDOP at 8, according to Microsoft */
    IF @MaxDOP > 8 SET @MaxDOP = 8;

    PRINT 'Suggested MAXDOP = ' + CAST(@MaxDOP as varchar(max));
END
ELSE
BEGIN
    PRINT 'Suggested MAXDOP = 0 since you have less than 4 cores total.';
    PRINT 'This is the default setting, you likely do not need to do';
    PRINT 'anything.';
END