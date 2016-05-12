-- enable backup compression by default
-- 2008: EE
-- 2008 R2 and newer: SE & up

-- Determine SQL Server Version / Edition
DECLARE	@ProductEdition NVARCHAR(50),
		@ProductVersion NVARCHAR(50),
		@Major			INT,
		@Minor			INT,
		@Build			INT,
		@Revision		INT

select	@ProductEdition = RTRIM(LTRIM(CONVERT(NVARCHAR(50), SERVERPROPERTY('Edition')))),
		@ProductVersion = RTRIM(LTRIM(CONVERT(NVARCHAR(50), SERVERPROPERTY('ProductVersion'))))

select	@Major		= 0
select	@Minor		= CHARINDEX('.', @ProductVersion, @Major + 1)
select	@Build		= CHARINDEX('.', @ProductVersion, @Minor + 1)
select	@Revision	= CHARINDEX('.', @ProductVersion, @Build + 1)

select	@Major		= CAST(SUBSTRING(@ProductVersion,@Major,@Minor) as int)
select	@Minor		= CAST(SUBSTRING(@ProductVersion,@Minor+1,@Build - @Minor - 1) as int)
select	@Build		= case	when @Revision > 0 then CAST(SUBSTRING(@ProductVersion,@Build+1,@Revision - @Build - 1) as int) 
							else CAST(SUBSTRING(@ProductVersion,@Build+1,LEN(@ProductVersion) - @Build) as int) end
select	@Revision	= case	when @Revision > 0 then CAST(SUBSTRING(@ProductVersion,@Revision+1,LEN(@ProductVersion) - @Revision) as int) 
							else 0 end

-- check version and adjust setting if possible
IF ((@Major = 10 AND @ProductEdition = 'Enterprise Edition') OR (@Major >= 10))
BEGIN
	EXEC sys.sp_configure 'backup compression default', '1'

	RECONFIGURE
END
GO