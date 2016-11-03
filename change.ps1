#This script will move objects from one OU to another and set AD Home folder path.

Clear-Host

write-host "This script will users' home directories to a destination path using the \\<path\<Username> form." -ForegroundColor Magenta

start-sleep -s 1

#Global Variables

$domain = "dc=lab,dc=local"

do
{



start-sleep -s 1



# Operator Variables.
$deptnamesource = read-host "What is the OU (eg OU=users,OU=LAB)"

$dest = read-host "what UNC path should I copy the Home Directory to? (eg \\crow\users)"

$maxcount = read-host "How many objects should I process?"

#Object/target variables

$targetou = "$deptnamesource,$domain"


$copycount=0
#Set AD Home Folder path and create/permission folder.
Get-ADUser -Filter * -SearchBase $targetou -properties homedirectory| Foreach-Object{
    #Collect VARs
    $sam = $_.SamAccountName
    $srcpath =  $_.HomeDirectory
    $dstpath = "$dest\$sam"
    # Ensure the HomeDirectory property is not blank
    if ($_.HomeDirectory -notlike "" -And $dstpath -notlike $srcpath -And $copycount -le $maxcount)  {
        $copycount++
        

        # Copy the user's Data
        robocopy $srcpath $dstpath /SEC /MIR /r:0 /w:0
        
        # Update the AD Property
        set-aduser -Identity $_ -HomeDirectory $dstpath

        #Remove permissions from old location
        icacls $srcpath /remove:g $sam /c 

        #Debug Info 
        write-host "Debug Info"   
        write-host "source: ",$srcpath
        write-host "dest: ",$dstpath
        write-host "Copy Count: $copycount"

    } else {
    write-host "skipping $sam"
    }

}

#Repeat process option.
write-host "All objects have been moved." -ForegroundColor Magenta



}

while ($choice -eq "Y")