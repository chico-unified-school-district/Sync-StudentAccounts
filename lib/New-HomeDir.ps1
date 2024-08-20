<#
Special Thanks to Jeff Hicks
https://petri.com/identify-folders-with-blocked-inheritance-using-powershell
#>
function New-HomeDir {
  [cmdletbinding()]
  param (
    [Parameter(Mandatory = $True)]
    [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
    [string]$FileServer,
    [Parameter(Mandatory = $True)]
    [string]$MyShare,
    [Parameter(Mandatory = $True)]
    [System.Management.Automation.PSCredential]$ServerCredential,
    [string]$Domain,
    [Parameter(Mandatory = $True)]
    [string]$Samid,
    [Parameter(Mandatory = $False)]
    [string[]]$ModifyAccess,
    [Parameter(Mandatory = $False)]
    [string[]]$FullAccess,
    [switch]$WhatIf
  )

  function Add-HomePath {
    process {
      $_.somePath = "$FileServer`:\$samid"
      $_
    }
  }
  function Add-DocsPath {
    process {
      $_.somePath = "$FileServer`:\$samid\Documents"
      $_
    }
  }
  function New-FullAccessObj {
    process {
      @{user = $_; type = 'FullControl' }
    }
  }
  function New-ModAccessObj {
    process {
      @{user = $_; type = 'Modify' }
    }
  }
  function New-ReadAccessObj {
    process {
      @{user = $_; type = 'ReadAndExecute' }
    }
  }
  function Remove-Inheritance {
    process {
      $acl = Get-Acl $_
      if ($acl.AreAccessRulesProtected -eq $false) {
        $acl.SetOwner([System.Security.Principal.NTAccount] $ServerCredential.UserName)
        Set-Acl $homePath $acl -WhatIf:$WhatIf
        $acl.SetAccessRuleProtection($true, $false)
        Set-Acl $homePath $acl -WhatIf:$WhatIf
      }
    }
  }
  function Set-Permissions {
    process {
      $acl = Get-Acl $_.somePath
      Write-Verbose ( '{0},Folder: {1},User: {2}, Access: {3}' -f $MyInvocation.MyCommand.name, $_.somePath, $_.user , $_.type)
      $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($_.user, $_.type, 'ContainerInherit,ObjectInherit', 'None', 'Allow')
      # Write-Verbose ( $accessRule | Out-String )
      if (-not($WhatIf)) {
        # Start-Sleep 5
        $acl.SetAccessRule($accessRule)
     (Get-Item $_.somePath).SetAccessControl($acl)
      }
    }
  }
  # ==============================================================================
  $TargetUser = $Domain + '\' + $Samid

  $homePath = "$FileServer`:\$samid"
  $docsPath = "$FileServer`:\$samid\Documents"

  New-PSDrive -name $FileServer -Root \\$FileServer\$MyShare -PSProvider FileSystem -Credential $ServerCredential | Out-Null

  if (-not(Test-Path $docsPath)) {
    New-Item -Path $docsPath -ItemType Directory -Confirm:$false -WhatIf:$WhatIf
  }
  if (Test-Path -Path $docsPath) {
    if ((Get-Acl $docsPath).Access.IdentityReference.Value -notcontains $TargetUser) {
      $uncPath = "\\{0}\{1}\{2}" -f $FileServer, $MyShare, $Samid
      Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $uncPath) -ForegroundColor Green
      if (-not($WhatIf)) { Start-Sleep 5 }
      $FullAccess += $ServerCredential.UserName
      $FullAccess | New-FullAccessObj | Add-HomePath | Set-Permissions
      #  $ModifyAccess | New-ModAccessObj | Add-HomePath | Set-Permissions
      $targetUser | New-ReadAccessObj | Add-HomePath | Set-Permissions
      $targetUser | New-ModAccessObj | Add-DocsPath | Set-Permissions
      $homePath | Remove-Inheritance
    }
  }

  Remove-PSDrive -Name $FileServer -Confirm:$false -Force
}