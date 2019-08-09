function Run-SQLCMD {
	[cmdletbinding()]
	param(
  [Parameter(Position=0,Mandatory=$True)]
  [string]$Server,
  [Parameter(Position=1,Mandatory=$True)]
  $Database,
  [Parameter(Position=2,Mandatory=$True)]
  $User,
  [Parameter(Position=3,Mandatory=$True)]
  [Alias('PW')]
  $Password,
  [Parameter(Position=4,Mandatory=$True)]
		[Alias('SQL','Query','SQLCMD')]
  $SQLStatement,
  [switch]$WhatIf
	)
 Write-Verbose "Running $($MyInvocation.MyCommand.Name)"
 if($WhatIf) { $SQLStatement } else {
  Write-Verbose "Begin querying database $Server\$DataBase as $User"
  if (Test-Connection -ComputerName $Server -Count 1 -Quiet){
   $ServerInstance = "$Server ";$Database = "$DataBase";$ConnectionTimeout = 60;$QueryTimeout = 120
   $conn=new-object System.Data.SqlClient.SQLConnection
   $ConnectionString = "Server={0};Database={1};Connect Timeout={2};User Id=$User;Password=$Password" -f $ServerInstance,$Database,$ConnectionTimeout
   $conn.ConnectionString=$ConnectionString; $conn.Open()
   $cmd=new-object system.Data.SqlClient.SqlCommand($SQLStatement,$conn)
   $cmd.CommandTimeout=$QueryTimeout
   $ds=New-Object system.Data.DataSet
   $da=New-Object system.Data.SqlClient.SqlDataAdapter($cmd)
   [void]$da.fill($ds)
   $conn.Close()
   $ds.Tables.Rows
  } else { "error,$Server not found." }
 }
}