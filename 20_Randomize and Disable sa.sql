

DECLARE @Password VARCHAR(50) ,
    @SQL VARCHAR(512) ,
    @PServer VARCHAR(128);

SELECT  @PServer = @@servername;

SELECT  @@SERVERNAME;

IF EXISTS ( SELECT  1
            FROM    sys.server_principals
            WHERE   name = 'sa'
                    AND is_disabled = 0 )
    BEGIN
        IF @PServer IS NULL
            OR @PServer NOT IN ( 'GPServer' )
            BEGIN
	
/*********************************************************************************************
PURPOSE:	Purpose of this object is to generate a random string of given length
----------------------------------------------------------------------------------------------
Comments:	Everything is self-explanatory.  Right now max length is set to 100. So anything
	between 1 and 100 will work for a length.

	If you specify a @charactersToUse, the bit flags get ignored.

	All spaces are stripped from the @charactersToUse.

	Characters can repeat. Will be handled in a future version.
----------------------------------------------------------------------------------------------
REVISION HISTORY:
Date			Developer Name			Change Description	
----------		--------------			------------------
05/16/2005		Raymond Lewallen		Original Version
05/14/2012		James N. Rzepka			Pulled from 'http://codebetter.com/raymondlewallen/2005/05/17/updated-random-password-or-string-generator-in-t-sql-for-sql-server/'
05/14/2012		James N. Rzepka			Updated to use special characters.
----------------------------------------------------------------------------------------------
***************************************************************************/
                DECLARE @useNumbers BIT = 1 ,
                    @useLowerCase BIT = 1 ,
                    @useUpperCase BIT = 1 ,
                    @useSpecial BIT = 1 ,
                    @charactersToUse AS VARCHAR(100) = NULL ,
                    @StringLength AS SMALLINT = 100 ,
                    @String VARCHAR(100);


                SET NOCOUNT ON;

                IF @StringLength <= 0
                    RAISERROR('Cannot generate a random string of zero length.',16,1);

                DECLARE @characters VARCHAR(100);
                DECLARE @count INT;

                SET @characters = '';

                IF @useSpecial = 1
                    BEGIN
	-- load up special characters
	--set @count = 32
	--while @count <=47
	--begin
	--	set @characters = @characters + Cast(CHAR(@count) as char(1))
	--	set @count = @count + 1
	--end
                        SET @characters = @characters + ' !#$%&()*+,-./@\^_`~';
                    END;

                IF @useNumbers = 1
                    BEGIN
	-- load up numbers 0 - 9
                        SET @count = 48;
                        WHILE @count <= 57
                            BEGIN
                                SET @characters = @characters
                                    + CAST(CHAR(@count) AS CHAR(1));
                                SET @count = @count + 1;
                            END;
                    END;

                IF @useUpperCase = 1
                    BEGIN
	-- load up uppercase letters A - Z
                        SET @count = 65;
                        WHILE @count <= 90
                            BEGIN
                                SET @characters = @characters
                                    + CAST(CHAR(@count) AS CHAR(1));
                                SET @count = @count + 1;
                            END;
                    END;

                IF @useLowerCase = 1
                    BEGIN
	-- load up lowercase letters a - z
                        SET @count = 97;
                        WHILE @count <= 122
                            BEGIN
                                SET @characters = @characters
                                    + CAST(CHAR(@count) AS CHAR(1));
                                SET @count = @count + 1;
                            END;
                    END;

                SET @count = 0;
                SET @String = '';

-- If you specify a character set to use, the bit flags get ignored.
                IF LEN(@charactersToUse) > 0
                    BEGIN
                        WHILE CHARINDEX(@charactersToUse, ' ') > 0
                            BEGIN
                                SET @charactersToUse = REPLACE(@charactersToUse,
                                                              ' ', '');
                            END;

                        IF LEN(@charactersToUse) = 0
                            RAISERROR('Cannot use an empty character set.',16,1);

                        WHILE @count <= @StringLength
                            BEGIN
    
                                SET @String = @String
                                    + SUBSTRING(@charactersToUse,
                                                CAST(ABS(CHECKSUM(NEWID()))
                                                * RAND(@count) AS INT)
                                                % LEN(@charactersToUse) + 1, 1);
                                SET @count = @count + 1;
                            END;
                    END;
                ELSE
                    BEGIN
                        WHILE @count <= @StringLength
                            BEGIN
    
                                SET @String = @String + SUBSTRING(@characters,
                                                              CAST(ABS(CHECKSUM(NEWID()))
                                                              * RAND(@count) AS INT)
                                                              % LEN(@characters)
                                                              + 1, 1);
                                SET @count = @count + 1;
                            END;
                    END;

                SET @Password = @String;

                SELECT  @SQL = '
		--Servername: ' + @@servername + '
		--PServer: ' + ISNULL(@PServer, '') + '
		USE [master]
		ALTER LOGIN [sa] WITH PASSWORD=''' + REPLACE(@Password, '''', '''''')
                        + '''
		ALTER LOGIN [sa] DISABLE
		';

		--PRINT @SQL
                EXEC (@SQL);
            END;
        ELSE
            PRINT '
		Servername: ' + @@servername + '
		PServer: ' + ISNULL(@PServer, '') + '
		No disable
		';
    END;