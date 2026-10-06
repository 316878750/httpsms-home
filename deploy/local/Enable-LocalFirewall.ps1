[CmdletBinding()]
param([Parameter(Mandatory)][string]$LanIP, [Parameter(Mandatory)][string]$LanCidr)
$ErrorActionPreference = 'Stop'
# Run from an elevated terminal after checking the supplied home-network values.
# Do not create a Public-profile rule or any router port-forwarding rule.
$name = 'httpSMS Local phone uploads'
if (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) { throw 'Rule already exists; inspect it before changing network settings.' }
New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol TCP -LocalAddress $LanIP -LocalPort 8444 -RemoteAddress $LanCidr -Profile Private
