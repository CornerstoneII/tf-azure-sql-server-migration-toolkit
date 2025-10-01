
--Bernard:  This script needs to be executed by the 'sa' (Thanos?) account -- use whatever you renamed 'sa' to on the new vm 

--=======================================================================================================================
--				CREATE MANAGED IDENTITY for Database Restoration
--=======================================================================================================================

-- Create login for the managed identity (replace with actual managed identity name)
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE type = 'E' AND name = 'mi-sql-tst-win')
BEGIN
    CREATE LOGIN [mi-sql-tst-win] FROM EXTERNAL PROVIDER;
    ALTER SERVER ROLE [sysadmin] ADD MEMBER [mi-sql-tst-win];
END;

--=======================================================================================================================
--				CREATE AZURE Server Principals for EntraID GROUPS
--=======================================================================================================================

use MASTER
GO
if not exists (select *	  from sys.server_principals  where type = 'X' and name	 = 'SoftwareEngineering')
begin
	create login SoftwareEngineering from external provider with DEFAULT_DATABASE = [Master];
end;

if not exists (select *	  from sys.server_principals  where type = 'X' and name	 = 'ProductInnovation')
begin
	create login ProductInnovation from external provider with DEFAULT_DATABASE = [Master];
end;

if not exists (select *	  from sys.server_principals  where type = 'X' and name	 = 'ProductExcellence')
begin
	create login ProductExcellence from external provider with DEFAULT_DATABASE = [Master];
end;



if not exists (select *	  from sys.server_principals  where type = 'X' and name	 = 'DataSystems')
begin
	create login DataSystems from external provider with DEFAULT_DATABASE = [Master];
end;


	if not exists (select *	  from sys.server_principals  where type = 'X' and name	 = 'SQLAdmins-Dev')
	begin

		create login [SQLAdmins-Dev] from external provider with DEFAULT_DATABASE = [Master];
	end;

	ALTER SERVER ROLE [sysadmin] ADD MEMBER [SQLAdmins-Dev]
GO


if not exists (select *	  from sys.server_principals  where type = 'X' and name	 = 'KMS Web Developers')
begin

	create login [KMS Web Developers] from external provider with DEFAULT_DATABASE = [master];
end;


--=======================================================================================================================
--				CREATE SERVER ROLE
--=======================================================================================================================
if not exists (select *	  from sys.server_principals  where type = 'R' and name	 = 'EWN')
begin

	create server role EWN authorization Thanos;																																										--Bernard:  Thanos should be changed to whatever you created as the 'sa' account on the new vm
end;


grant view any definition to EWN;
grant view server state to EWN;
GRANT ALTER ANY EVENT SESSION TO EWN;


alter server role EWN add member SoftwareEngineering;
alter server role EWN add member ProductInnovation;
alter server role EWN add member DataSystems;
alter server role EWN add member ProductExcellence;

--=======================================================================================================================
--				Add Azure Groups to db_owner role in each database
--=======================================================================================================================

use DataWarehouse;
	     alter role db_owner add member SoftwareEngineering;
		 alter role db_owner add member DataSystems
		 alter role db_owner add member ProductInnovation
		 alter role db_owner add member ProductExcellence
		GRANT SHOWPLAN TO SoftwareEngineering;
		GRANT SHOWPLAN TO DataSystems;
		GRANT SHOWPLAN TO ProductInnovation;
		GRANT SHOWPLAN TO ProductExcellence;

use EWN;
	     alter role db_owner add member SoftwareEngineering;
		 alter role db_owner add member DataSystems
		 alter role db_owner add member ProductInnovation
		 alter role db_owner add member ProductExcellence
		GRANT SHOWPLAN TO SoftwareEngineering;
		GRANT SHOWPLAN TO DataSystems;
		GRANT SHOWPLAN TO ProductInnovation;
		GRANT SHOWPLAN TO ProductExcellence;

use Rustici;
	     alter role db_owner add member SoftwareEngineering;
		 alter role db_owner add member DataSystems
		 alter role db_owner add member ProductInnovation
		 alter role db_owner add member ProductExcellence
		GRANT SHOWPLAN TO SoftwareEngineering;
		GRANT SHOWPLAN TO DataSystems;
		GRANT SHOWPLAN TO ProductInnovation;
		GRANT SHOWPLAN TO ProductExcellence;

use Quartz;
	     alter role db_owner add member SoftwareEngineering;
		 alter role db_owner add member DataSystems
		 alter role db_owner add member ProductInnovation
		 alter role db_owner add member ProductExcellence
		GRANT SHOWPLAN TO SoftwareEngineering;
		GRANT SHOWPLAN TO DataSystems;
		GRANT SHOWPLAN TO ProductInnovation;
		GRANT SHOWPLAN TO ProductExcellence;
