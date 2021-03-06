[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript( {Test-Path $_ -PathType 'Container'})] 
    [string]$InstallPath,
    [Parameter(Mandatory = $true)]
    [ValidateScript( {Test-Path $_ -PathType 'Container'})] 
    [string]$DataPath,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()] 
    [string]$SqlHostname,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DatabasePrefix
)

$noDatabases = (Get-ChildItem -Path $DataPath -Filter "*.mdf") -eq $null

if ($noDatabases)
{
    Write-Host "### Sitecore databases not found in '$DataPath', seeding clean databases..."

    Get-ChildItem -Path $InstallPath | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $DataPath
    }
}
else
{
    Write-Host "### Existing Sitecore databases found in '$DataPath'..."
}

Get-ChildItem -Path $DataPath -Filter "*.mdf" | ForEach-Object {
    $databaseName = $_.BaseName.Replace("_Primary", "")
    $mdfPath = $_.FullName
    $ldfPath = $mdfPath.Replace(".mdf", ".ldf")
    $sqlcmd = "IF EXISTS (SELECT 1 FROM SYS.DATABASES WHERE NAME = '$databaseName') BEGIN EXEC sp_detach_db [$databaseName] END;CREATE DATABASE [$databaseName] ON (FILENAME = N'$mdfPath'), (FILENAME = N'$ldfPath') FOR ATTACH;"

    Write-Host "### Attaching '$databaseName'..."

    Invoke-Sqlcmd -Query $sqlcmd
}

Write-Host "### Preparing Sitecore databases..."

# See http://jonnekats.nl/2017/sql-connection-issue-xconnect/ for details...
Invoke-Sqlcmd -Query ("EXEC sp_MSforeachdb 'IF charindex(''{0}'', ''?'' ) = 1 BEGIN EXEC [?]..sp_changedbowner ''sa'' END'" -f $env:DB_PREFIX)
Invoke-Sqlcmd -Query ("UPDATE [{0}_Xdb.Collection.ShardMapManager].[__ShardManagement].[ShardsGlobal] SET ServerName = '{1}'" -f $env:DB_PREFIX, $SqlHostname)
Invoke-Sqlcmd -Query ("UPDATE [{0}_Xdb.Collection.Shard0].[__ShardManagement].[ShardsLocal] SET ServerName = '{1}'" -f $env:DB_PREFIX, $SqlHostname)
Invoke-Sqlcmd -Query ("UPDATE [{0}_Xdb.Collection.Shard1].[__ShardManagement].[ShardsLocal] SET ServerName = '{1}'" -f $env:DB_PREFIX, $SqlHostname)

Write-Host "### Sitecore databases ready!"

# Call Start.ps1 from the base image https://github.com/Microsoft/mssql-docker/blob/master/windows/mssql-server-windows-developer/dockerfile
& C:\Start.ps1 -sa_password $env:SA_PASSWORD -ACCEPT_EULA $env:ACCEPT_EULA -attach_dbs \"$env:attach_dbs\" -Verbose
