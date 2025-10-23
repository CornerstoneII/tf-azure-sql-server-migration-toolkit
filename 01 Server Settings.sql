

/* Server Level Configuration Settings */
use master;
GO
EXECUTE sp_configure 'show advanced options', 1;
GO
reconfigure  WITH OVERRIDE;
GO
EXECUTE sp_configure 'nested triggers', 1;
GO
RECONFIGURE;
go

EXEC sp_configure 'remote admin connections', 1 ;  
RECONFIGURE;
go

EXEC sys.sp_configure N'cost threshold for parallelism', N'50'
reconfigure
GO

EXECUTE sp_configure 'show advanced options', 0;
GO
reconfigure  WITH OVERRIDE;
GO