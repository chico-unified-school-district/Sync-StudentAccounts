<#
Made possible By Steve Parankewich
http://powershellblogger.com/2016/01/create-shortcuts-lnk-or-url-files-with-powershell/
#>
function Create-GSuiteURL {
	[cmdletbinding()]
	param (
  [Parameter(Position = 0, Mandatory = $True)]
  [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
  [Alias('Server')]
  [string]$FileServer,
  [Parameter(Position = 1, Mandatory = $True)]
  [Alias('Share')]
  [string]$ShareName,
  [Parameter(Position = 2, Mandatory = $True)]
  [string]$samid,
  [Parameter(Position = 3, Mandatory = $True)]
  [Alias('Cred')]
  [System.Management.Automation.PSCredential]$ServerCredential,
  [switch]$WhatIf
	)

 Write-Verbose "Running $($MyInvocation.MyCommand.Name)"

 if ($WhatIf) { "[TEST],$samid,$samid@chicousd.net.url" }
 else {
  # Begin Create URL
  $homeDir = "\\$FileServer\$ShareName\$samid\Documents"
  
  Write-Verbose "Adding PSDrive"
  New-PSDrive -name share -root $homeDir -PSProvider FileSystem -Credential $ServerCredential | Out-Null
  if (!(Test-Path -Path "share:\$samid@chicousd.net.url")) {
   Write-Verbose "Creating GSuite shortcut for $samid on $FileServer."
   $newFile = @(
    '[InternetShortcut]'
    'URL=http://bit.ly/cusdgsuitestudent'
    'IDList='
    'HotKey=0'
    'IconIndex=0'
    'IconFile=\\chico.usd\netlogon\CUSD\Icons\cusd_seal_icon.ico'
    '[{000214A0-0000-0000-C000-000000000046}]'
   )
   $newFile | Out-File -FilePath "share:\$samid@chicousd.net.url" -Force
    
   if (Test-Path -Path "share:\$samid@chicousd.net.url") {
    Write-Verbose "URL Created,$homeDir\$samid@chicousd.net.url"
   }
   else { "ERROR,Shortcut not created,$homeDir\$samid@chicousd.net.url" }
  }
  Write-Verbose "Removing PSDrive"
  Remove-PSDrive -Name share -Confirm:$false -Force | Out-Null
 } # End Create URL
} # End Function
