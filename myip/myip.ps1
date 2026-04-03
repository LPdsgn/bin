Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -ne '127.0.0.1' } |
  ForEach-Object { "{0}  |  {1}" -f $_.IPAddress, $_.InterfaceAlias }
