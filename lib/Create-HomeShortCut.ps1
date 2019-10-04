<#
Made possible By Kris
https://www.pdq.com/blog/pdq-deploy-and-powershell/
#>
function Create-HomeShortCut {
	[cmdletbinding()]
	param (
  [Parameter(Position = 0, Mandatory = $True)]
  [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
  [Alias('Server')]
  [string]$FileServer,
  [Parameter(Position = 1, Mandatory = $True)]
  [string]$ShareName,
  [Parameter(Position = 2, Mandatory = $True)]
  [string]$samid,
  [Parameter(Position = 3, Mandatory = $True)]
  [Alias('Cred')]
  [System.Management.Automation.PSCredential]$ServerCredential,
  [Parameter(Position = 4, Mandatory = $True)]
  [string]$OldHomePath,
  [switch]$WhatIf
	)
 Write-Verbose "Running $($MyInvocation.MyCommand.Name)"
 # Clear old connections
 net use * /delete /y
 # Check for old H Drive
 $oldServerName = $OldHomePath.Split('\')[2]
 $fileName = "Old H-Drive - $oldServerName.lnk"
 $homeDir = "\\$FileServer\$ShareName\$samid\Documents"

 try {
  Write-Verbose "Adding PSDrive"
  New-PSDrive -name TempDrive -root $homeDir -PSProvider FileSystem -Credential $ServerCredential -ErrorAction STOP | Out-Null
  # Get-PSDrive -Name TempDrive
 }
 catch {
  '{1} - Unable to map path' -f $OldHomePath
  # '{1} - Unable to map path' -f $OldHomePath | Out-file .\oldhome2.txt -Append
  continue
 }

 try {
  $dataSize = ([math]::Round((Get-ChildItem TempDrive: -Recurse -ErrorAction STOP | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum / 1KB))
  # "{0} KB" -f $dataSize
 }
 catch {
  Write-Verbose ('No data on {0}' -f $oldHomePath )
 }

 if ($dataSize -gt 0 ) {
  if ($WhatIf) { '[TEST],{0},{1},{2}' -f $samid, "\\$FileServer\$ShareName", $OldHomePath }
  else {
   # Begin Create Shortcut
   if (!(Test-Path -Path "share:\Old H-Drive $samid.lnk")) {
    Write-Verbose "Creating Old H Drive shortcut for $samid on $FileServer."
    $TargetFile = "$OldHomePath"
    $ShortcutFile = $fileName
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
    $Shortcut.TargetPath = $TargetFile
    if ($WhatIf) { $Shortcut }
    else { $Shortcut.Save() }
    $fullPath = $Shortcut.FullName
    Move-Item -Path $fullPath -Destination TempDrive: -Confirm:$false -Force
  
    if (Test-Path -Path "TempDrive:\$fileName") {
     "Shortcut to $OldHomePath created at $homeDir"
    }
    else { "ERROR,{0},{1} Shortcut not created" -f $samid, $FileServer }
   }
  } # End Create Shortcut
  Write-Verbose "Removing PSDrive"
  Remove-PSDrive -Name TempDrive -Confirm:$false -Force | Out-Null
 }
} # End Function
