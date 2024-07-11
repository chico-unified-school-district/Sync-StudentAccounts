function New-ADSession ($dc, $cmdlets, $myUser) {
 $msgVars = $MyInvocation.MyCommand.Name, $dc, ($cmdLets -join ',')
 Write-Verbose ('{0},{1}' -f $msgVars)
 $adSession = New-PSSession -ComputerName $dc -Credential $myUser
 $sessionParams = @{
  Session      = $adSession
  Module       = 'ActiveDirectory'
  CommandName  = $cmdLets
  AllowClobber = $true
  ErrorAction  = 'SilentlyContinue'
 }
 Import-PSSession @sessionParams | Out-Null
}