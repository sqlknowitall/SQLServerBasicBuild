SELECT
	CASE
		WHEN is_read_only = 1
			THEN 'ALTER DATABASE ['+name+'] SET READ_WRITE'+CHAR(10)+
				'GO'+CHAR(10)
			ELSE ''
	END+
	'ALTER AUTHORIZATION ON DATABASE::['+name+'] TO sa;'+CHAR(10)+
	'GO'+CHAR(10)+
	CASE
		WHEN is_read_only = 1
			THEN 'ALTER DATABASE ['+name+'] SET READ_ONLY'+CHAR(10)+
				'GO'+CHAR(10)
			ELSE ''
	END AS Script, suser_sname(owner_sid) AS CurrentOwner
from sys.databases with (nolock)
where name not in ('master', 'model', 'msdb', 'tempdb') and
suser_sname(owner_sid) <> 'sa'
AND state = 0
ORDER BY name
