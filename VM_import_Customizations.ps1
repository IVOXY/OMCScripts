$credentials = Get-Credential
$admincred = Get-Credential
$userobjects = Import-Csv C:\Scripts\VM_import.csv
Connect-VIServer vc10prod1 -Credential $credentials
#####################################################
#      Update Template(s) Listed In Import CSV      #
#           						                #
#####################################################
foreach ($image in $userobjects)
{ if ($image.template -eq "") {}
else { 
	#$updatetmplt +=@($image.template)
	if ($updatetmplt -contains $image.Template){}
	else {$updatetmplt += @($image.template)}
	}
	}
	foreach ($template in $updatetmplt){
	Write-Host "Starting Process of Updating Template "$template""
	Set-Template -template $template -ToVM | Out-Null
	Start-VM -VM $template | Out-Null
	Start-Sleep -Seconds 120
	
	$WSUS = "Get-WUInstall -WindowsUpdate -AutoReboot:`$true -AcceptAll"
	Write-Host "Installing Windows Updates on "$template". This can take a long time. Please be patient"
	Invoke-VMScript -VM $template -HostCredential $credentials -GuestCredential $admincred -ScriptType Powershell -ScriptText $WSUS
	
	Start-Sleep -Seconds 300
	Stop-VMGuest -VM $template -Confirm:$false
	Start-Sleep -Seconds 120
	Set-VM -ToTemplate -VM $template -Confirm:$false
}

#####################################################
#      Create new VM based off Template             #
#        with Customized VM Settings                #
#####################################################
foreach ($vm in $userobjects)
{
	if ($vm.MemSize -ne ""){
		Write-Host "Creating new VM called "$vm.VMName""
	
		New-VM -Name $vm.vmname  -Template $vm.Template -Datastore $vm.datastore  -ResourcePool Resources -Location $vm.Folder | Out-Null
	
	#Creates non-OS disk to selected VM's
		New-HardDisk -VM $vm.VMName -DiskType flat -Persistence persistent -CapacityGB $vm.DiskSize -StorageFormat Thin -Confirm:$false  | Out-Null

	#Modifies Memory, CPU, and adds Attribute notes
		Set-VM -VM $vm.vmname -MemoryGB $vm.MemSize -NumCpu $vm.CPUCount -Notes $vm.Notes -Confirm:$false | Out-Null
	
	#Sets Network Adapter of VM to assigned network
		get-networkadapter -vm $vm.vmname | Set-NetworkAdapter -NetworkName $vm.Network -Confirm:$false  | Out-Null
	}
	else{
	#Creates additional disk(s) to selected VM's (isolated to this line when more than 2 disks are required)
			New-HardDisk -VM $vm.VMName -DiskType flat -Persistence persistent -CapacityGB $vm.DiskSize -StorageFormat Thin   -Confirm:$false | Out-Null
		}
	#starts VM
	if ($vm.MemSize -ne ""){
		Write-Host "powering on "$vm.VMName""
		Start-VM -VM $vm.vmname | Out-Null
		}
		else {}	
}		

#####################################################
#       allow time for VM to boot                   #
#####################################################
if ($vm.MemSize -ne ""){
	Write-Host "Sleeping for 30 seconds while we boot "$vm.VMName""
	Start-Sleep -Seconds 30}
else {}

#####################################################
#       Begin OS Customization                      #
#####################################################
foreach ($vm in $userobjects)
{ if ($vm.MemSize -ne ""){
#Set static IP Address
	$vminfo = (Get-VMGuest -VM $vm.VMName)
	$ip = $vm.IPAddress
	$SM = $vm.SubMask
	$GW = $vm.gateway
	$DNS1 = "10.203.14.100"
	$DNS2 = "10.203.14.101"
	$netsh1 = "c:\windows\system32\netsh.exe interface ipv4 set address ""Ethernet"" static $ip $SM $GW 1"
		Write-Host "Configuring "$vm.VMName" Network Settings"
		Invoke-VMScript -VM $vm.VMName -HostCredential $credentials -GuestCredential $admincred -ScriptType Bat -ScriptText $netsh1 | Out-Null

#Set DNS Servers 
	$netsh2 = "c:\windows\system32\netsh.exe dnsclient set dnsservers name=""Ethernet"" source=static address=$DNS1"
	$netsh3 = "c:\windows\system32\netsh.exe dnsclient add dnsservers name=""Ethernet"" address=$DNS2 index=2"
		Write-Host "setting DNS servers for "$vm.VMName""
		Invoke-VMScript -VM $vm.VMName -HostCredential $credentials -GuestCredential $admincred -ScriptType Bat -ScriptText $netsh2 | Out-Null
		Invoke-VMScript -VM $vm.VMName -HostCredential $credentials -GuestCredential $admincred -ScriptType Bat -ScriptText $netsh3 | Out-Null

# allow time for NIC to connect
	Start-Sleep -Seconds 15

#####################################################
#              Add to Domain	                    #
#####################################################
Write-Host "Renaming in the OS to "$vm.vmname""
Rename-Computer -ComputerName $ip -NewName $vm.VMName -LocalCredential $admincred -DomainCredential $credentials | Out-Null
Write-Host "restarting "$vm.VMName" to effect name change. Please wait 2 minutes"
Restart-VMguest -VM $vm.vmname  -Confirm:$false | Out-Null
Start-Sleep -Seconds 120
Write-Host "Adding "$vm.VMName" to OMH domain"
Add-Computer -ComputerName $ip -DomainName olympicmedical.local -LocalCredential $admincred -OUPath "OU=servers;DC=olympicmedical;DC=local" -Credential $credentials | Out-Null
Start-Sleep -Seconds 15
Write-Host "restarting "$vm.VMName" to effect domain add. Please wait 2 minutes"
Restart-VMguest -VM $vm.vmname -Confirm:$false | Out-Null
Start-Sleep -Seconds 120

#####################################################
#     Check for and install Windows Updates         #
#####################################################

	$WSUS = "Get-WUInstall -WindowsUpdate -AutoReboot:`$true -AcceptAll"
	Write-Host "Installing Windows Updates on "$vm.VMName". This can take a long time. Please be patient"
	Invoke-VMScript -VM $vm.VMName -HostCredential $credentials -GuestCredential $credentials -ScriptType Powershell -ScriptText $WSUS | Out-Null
}
else {}
}

