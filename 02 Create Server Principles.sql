
-- This script is executed by the Yoda account (sysadmin) during automated deployment
-- Managed identity login creation is handled separately by sql-setup-fixed.ps1
-- This script focuses on creating Azure AD group logins and custom server roles

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

	create server role EWN authorization Yoda;
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
