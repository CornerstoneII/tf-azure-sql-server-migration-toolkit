use master

-- Creates the Managed Identity that you added to Azure as a login on the server and a user in each database with appropriate permissions needed by our web app
--you will need to deal with variables to customize the name of the managed identity.  

if not exists(select * from sys.server_principals where name = 'miPR####Secrets')
		begin
			create login [miPR####Secrets] from external provider;   -- at this point, this Managed Identity has no permissions (in your script you temporarily gave it sysadmin but we don't want to keep that forever)
		end

		
--These commands can only be run after the databases have been restored


use DataWarehouse;
	if not exists (select *	  from sys.database_principals where name	 ='miPR####Secrets')
		create user [miPR####Secrets] for login [miPR####Secrets];

		alter role db_datareader add member [miPR####Secrets];
		alter role db_datawriter add member [miPR####Secrets];
		alter role db_executor add member [miPR####Secrets];

use EWN;
	if not exists (select *	  from sys.database_principals where name	 ='miPR####Secrets')
		create user [miPR####Secrets] for login [miPR####Secrets];

		alter role db_datareader add member [miPR####Secrets];
		alter role db_datawriter add member [miPR####Secrets];
		alter role db_executor add member [miPR####Secrets];

use Rustici;
	if not exists (select *	  from sys.database_principals where name	 ='miPR####Secrets')
		create user [miPR####Secrets] for login [miPR####Secrets];

		alter role db_datareader add member [miPR####Secrets];
		alter role db_datawriter add member [miPR####Secrets];
		alter role db_executor add member [miPR####Secrets];

use Quartz;
	if not exists (select *	  from sys.database_principals where name	 ='miPR####Secrets')
		create user [miPR####Secrets] for login [miPR####Secrets];

		alter role db_datareader add member [miPR####Secrets];
		alter role db_datawriter add member [miPR####Secrets];
		alter role db_executor add member [miPR####Secrets];

