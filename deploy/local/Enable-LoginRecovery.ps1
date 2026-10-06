[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$resume = Join-Path $PSScriptRoot 'Resume-Local.ps1'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $resume + '"'
$name = 'httpSMS Home Recovery'
$existing = (Get-ItemProperty -LiteralPath $runKey -Name $name -ErrorAction SilentlyContinue).$name
if ($existing -and $existing -ne $command) { throw 'A different recovery command already exists; inspect it before replacing.' }
$task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
if ($task -and -not (@($task.Actions) | Where-Object { $_.Arguments.Contains('"' + $resume + '"') })) { throw 'A different task already uses this name.' }
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $resume + '" -TriggerSource ScheduledTask')
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$trigger.Delay = 'PT15S'
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Restore local httpSMS services after this user logs in.' -Force | Out-Null
if ($existing -eq $command) { Remove-ItemProperty -LiteralPath $runKey -Name $name }
Write-Output 'Home recovery scheduled at user login, with delayed start and failure retries.'
