Import-Module ActiveDirectory
Import-Module NTFSsecurity
Import-Module SmbShare
$users          = Import-CSV "C:\users.csv"
$NetBios        = "adrarform"
$DomainDN       = "DC=$NetBios,DC=local"
$adrarOUDN      = "OU=$NetBios,$DomainDN"
$mainPath       = "C:\Share"
$mainDirectories = @(
    $mainPath,
    "$mainPath\Administrative Team",
    "$mainPath\Administrative Team\Common Space",
    "$mainPath\Administrative Team\Private Space",
    "$mainPath\Classes",
    "$mainPath\Teachers Ressources"
)
$OUNames = @("Students", "Teachers", "Administrative")
$GHT = @{
    GroupCategory = "Security"
    GroupScope    = "Global"
}

if (!(Get-ADOrganizationalUnit -Filter {Name -eq $NetBios})) {
    Write-Host "`n`nCreating the $NetBios OU!" -ForegroundColor Green
    New-ADOrganizationalUnit -Name $NetBios -Path $DomainDN
}
foreach ($OUName in $OUNames) {
    $OUDN = "OU=$OUName,$adrarOUDN"
    if (!(Get-ADOrganizationalUnit -Filter {Name -eq $OUName})) {
        Write-Host "Creating the $OUName OU!" -ForegroundColor Green
        New-ADOrganizationalUnit -Name $OUName -Path $adrarOUDN
        New-ADGroup -Name "gg-$OUName" @GHT -Path $OUDN
    }
}
foreach ($maindirectory in $mainDirectories) {
    if (!(Test-Path -Path $maindirectory -PathType Container )) {
        New-Item -ItemType Directory $maindirectory > $null
        Write-Host "$maindirectory has beed created." -ForegroundColor Green
        Clear-NTFSAccess -Path $maindirectory -DisableInheritance
        Add-NTFSAccess -Path $maindirectory -Account "$NetBios\Domain Admins" -AccessRights "FullControl"
        switch ($maindirectory) {
            $mainPath {
                Add-NTFSAccess -Path $maindirectory -Account "$NetBios\Domain Users"`
                 -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
            }
            $($mainDirectories[1]) {
                Add-NTFSAccess -Path $maindirectory -Account "$NetBios\gg-$($OUNames[2])"`
                 -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
            }
            $($mainDirectories[2]) {
                Add-NTFSAccess -Path $maindirectory -Account "$NetBios\gg-$($OUNames[2])"`
                 -AccessRights ReadAndExecute,Write -AppliesTo ThisFolderOnly
                Add-NTFSAccess -Path $maindirectory -Account "$NetBios\gg-$($OUNames[2])"`
                 -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
                Add-NTFSAccess -Path $maindirectory -Account "CREATOR OWNER"`
                 -AccessRights Modify -AppliesTo SubfoldersAndFilesOnly
            }
            $($mainDirectories[3]) {
                Add-NTFSAccess -Path $maindirectory -Account "$NetBios\gg-$($OUNames[2])"`
                 -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
            }
            $($mainDirectories[4]) {
                Add-NTFSAccess -Path $maindirectory -Account "$NetBios\gg-$($OUNames[0])"`
                 -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
                Add-NTFSAccess -Path $maindirectory -Account "$NetBios\gg-$($OUNames[1])"`
                 -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
            }
            default {
                Add-NTFSAccess -Path $maindirectory -Account "$NetBios\gg-$($OUNames[1])"`
                 -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
            }
        }
    }
}

$shareExist = Get-SmbShare $NetBios -ErrorAction SilentlyContinue
if (!($shareExist)) {
    New-SMBShare -Name $NetBios -Path "C:\Share"
    Revoke-SmbShareAccess -Name $NetBios -AccountName "everyone" -Confirm:$false
    Grant-SmbShareAccess -Name $NetBios -AccountName "$NetBios\domain users"`
     -AccessRight Change -Confirm:$false
     Grant-SmbShareAccess -Name $NetBios -AccountName "$NetBios\domain admins"`
     -AccessRight Full -Confirm:$false
    Get-SmbShare $NetBios | Set-SmbShare -FolderEnumerationMode AccessBased -Confirm:$false
    Write-Host "$NetBios share folder has been configured." -ForegroundColor Green
} else {
    Write-Host "Main share folder: $NetBios is already configured!" -ForegroundColor Yellow
}


foreach ($user in $users) {
    $usertype       = $user.usertype
    $firstName      = $user.FirstName
    $lastName       = $user.LastName
    $SlastName      = $user.LastName -replace "\s", ""
    $Name           = $firstName.Substring(0,1).ToUpper() + $SlastName.ToLower()
    $Password       = ConvertTo-SecureString "Azerty77" -AsPlainText -Force
    $NUserHT = @{
        SamAccountName      = $Name
        Name                = $Name
        GivenName           = $firstName
        Surname             = $lastName 
        DisplayName         = "$firstName $lastName"
        AccountPassword     = $Password
        Enabled             = $true
        Description         = "$firstName $lastName"
    }
    try {
        New-ADUser @NUserHT
        Set-ADUser -Identity $Name -HomeDirectory "\\DC01\$NetBios" -HomeDrive H:
        Write-Host "New account $Name has been created for $firstName $lastName and added to $ggCohort group"`
        -ForegroundColor Blue
    } catch {
        Write-Host "The account $Name for $firstName $lastName already exist."`
        -ForegroundColor Yellow
    }

#########
# IF the user is a student
#########
    if ($usertype -eq "student") {
        [string]$StartDate  = $user.StartDate
        [string]$EndDate    = $user.EndDate
        $cohort          = $user.Cohort.ToLower()
        $ouCohort        = "ou-$cohort"
        $ggCohort        = "gg-$cohort"
        $ouPath         = "OU=$ouCohort,OU=$($OUNames[0]),$adrarOUDN"
        Set-ADUser $Name -Add @{StartDate=$StartDate}
        Set-ADUser $Name -Add @{EndDate=$EndDate}
    
        if (!(Get-ADOrganizationalUnit -Filter {Name -eq $ouCohort})) {
            Write-Host "New Cohort! Creating the OU..." -ForegroundColor Green
            New-ADOrganizationalUnit -Name $ouCohort -Path "OU=$($OUNames[0]),$adrarOUDN"
        }
        if (!(Get-ADGroup -Filter {Name -eq $ggCohort})) {
            Write-Host "Creating $ggCohort group..." -ForegroundColor Green
            $NewGroupHT = @{
                Name            = $ggCohort
                GroupCategory   = "security"
                GroupScope      = "Global"
                Path            = $ouPath
                Description     = "Group for $cohort Cohort"
            }
            New-ADGroup @NewGroupHT
            Add-ADGroupMember -Identity "gg-$($OUNames[0])" -Members $ggCohort
            Write-Host "the group $ggCohort has been added to the group gg-$($OUNames[0])"`
            -ForegroundColor Green
        }
        Try { Move-ADObject -Identity "CN=$Name,CN=Users,$DomainDN" -TargetPath $ouPath }
        Catch { Write-Host "User $Name does not exist in Users OU" -ForegroundColor Yellow}

        $pathCohort = "$($mainDirectories[4])\$cohort"
        $studentsDirectories = @( 
            "$pathCohort", 
            "$pathCohort\$($OUNames[0])", 
            "$pathCohort\$($OUNames[0]) Common", 
            "$pathCohort\$($OUNames[1]) Common" 
        )
        foreach ($studentDirectory in $studentsDirectories) {
            if (!(Test-Path $studentDirectory)) {
                New-Item -ItemType Directory -Path $studentDirectory > $null
                Write-Host "$studentDirectory has beed created." -ForegroundColor Green
                Clear-NTFSAccess -Path $studentDirectory -DisableInheritance
                Add-NTFSAccess -Path $studentDirectory -Account "$NetBios\domain admins"`
                 -AccessRights "FullControl"
                if ($studentDirectory -eq $($studentsDirectories[0]) -or $studentDirectory -eq $($studentsDirectories[1])) {
                    Add-NTFSAccess -Path $studentDirectory -Account $ggCohort -AccessRights "ReadAndExecute"
                    Add-NTFSAccess -Path $studentDirectory -Account "$NetBios\gg-$($OUNames[1])"`
                     -AccessRights "ReadAndExecute"
                }
                elseif ($studentDirectory -eq $($studentsDirectories[2])) {
                    Add-NTFSAccess -Path $studentDirectory -Account "$NetBios\$ggCohort"`
                     -AccessRights ReadAndExecute,Write -AppliesTo ThisFolderOnly
                    Add-NTFSAccess -Path $studentDirectory -Account "$NetBios\$ggCohort"`
                     -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
                    Add-NTFSAccess -Path $studentDirectory -Account "$NetBios\gg-$($OUNames[1])"`
                     -AccessRights ReadAndExecute,Write -AppliesTo ThisFolderOnly
                    Add-NTFSAccess -Path $studentDirectory -Account "$NetBios\gg-$($OUNames[1])"`
                     -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
                    Add-NTFSAccess -Path $studentDirectory -Account "CREATOR OWNER"`
                     -AccessRights Modify -AppliesTo SubfoldersAndFilesOnly
                }
                else {
                    Add-NTFSAccess -Path $studentDirectory -Account "$NetBios\gg-$($OUNames[1])"`
                     -AccessRights ReadAndExecute,Write -AppliesTo ThisFolderOnly
                    Add-NTFSAccess -Path $studentDirectory -Account "$NetBios\gg-$($OUNames[1])"`
                     -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
                    Add-NTFSAccess -Path $studentDirectory -Account "CREATOR OWNER"`
                     -AccessRights Modify -AppliesTo SubfoldersAndFilesOnly
                    Add-NTFSAccess -Path $studentDirectory -Account "$NetBios\gg-$($OUNames[0])"`
                     -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
                }
                if ($studentDirectory -eq $studentsDirectories[3]) {
                    foreach ($gg in @($ggCohort, "gg-$($OUNames[1])", "domain admins")) {
                        Add-NTFSAudit -Path $studentDirectory -AccessRights "Modify"`
                         -Account "$NetBios\$gg"
                        Write-Host "Auditing has been configured for $gg group on $studentDirectory directory."`
                         -ForegroundColor Green
                    }
                }
            }
        }
        if (!(Test-Path "$($studentsDirectories[1])\$Name")) {
            New-Item -ItemType Directory -Path "$($studentsDirectories[1])\$Name" > $null
            Write-Host "$($studentsDirectories[1])\$Name has beed created." -ForegroundColor Green
            Clear-NTFSAccess -Path "$($studentsDirectories[1])\$Name" -DisableInheritance
            Add-NTFSAccess -Path "$($studentsDirectories[1])\$Name" -Account "$NetBios\domain admins"`
             -AccessRights "FullControl"
            Add-NTFSAccess -Path "$($studentsDirectories[1])\$Name" -Account "$NetBios\gg-$($OUNames[1])"`
             -AccessRights ReadAndExecute,Write -AppliesTo ThisFolderOnly
            Add-NTFSAccess -Path "$($studentsDirectories[1])\$Name" -Account "$NetBios\gg-$($OUNames[1])"`
             -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
            Add-NTFSAccess -Path "$($studentsDirectories[1])\$Name" -Account "$NetBios\$Name"`
             -AccessRights ReadAndExecute,Write -AppliesTo ThisFolderOnly
            Add-NTFSAccess -Path "$($studentsDirectories[1])\$Name" -Account "$NetBios\$Name"`
             -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
            Add-NTFSAccess -Path "$($studentsDirectories[1])\$Name" -Account "CREATOR OWNER"`
             -AccessRights Modify -AppliesTo SubfoldersAndFilesOnly
        } else {
            Write-Host "$($studentsDirectories[1])\$Name already exist!" -ForegroundColor Yellow
        }
#########
# IF the user is a teacher
#########
    } elseif ($usertype -eq "teacher") {
        $discipline      = $user.discipline.ToUpper()
        $ouPath         = "OU=$($OUNames[1]),$adrarOUDN"
        $ggdiscipline    = "gg-$discipline"
        Try { Move-ADObject -Identity "CN=$Name,CN=Users,$DomainDN" -TargetPath $ouPath }
        Catch { Write-Host "User $Name does not exist in Users OU" -ForegroundColor Yellow}
        if (!(Get-ADGroup -Filter {Name -eq $ggdiscipline})) {
            Write-Host "Creating $ggdiscipline group..." -ForegroundColor Green
            $NewGroupHT = @{
                Name            = $ggdiscipline
                GroupCategory   = "security"
                GroupScope      = "Global"
                Path            = $ouPath
                Description     = "Group for $ggdiscipline Cohort"
            }
            New-ADGroup @NewGroupHT
            Add-ADGroupMember -Identity "gg-$($OUNames[1])" -Members $ggdiscipline
            Write-Host "the group $ggdiscipline has been added to the group gg-$($OUNames[0])"`
            -ForegroundColor Green
        }
        $disciplineDirectory    = "$($mainDirectories[5])\$discipline"
        if (!(Test-Path $disciplineDirectory)) {
            New-Item -ItemType Directory -Path $disciplineDirectory > $null
            Write-Host "$disciplineDirectory has beed created." -ForegroundColor Green
            Clear-NTFSAccess -Path $disciplineDirectory -DisableInheritance
            Add-NTFSAccess -Path $disciplineDirectory -Account "$NetBios\domain admins"`
             -AccessRights "FullControl"
            Add-NTFSAccess -Path $disciplineDirectory -Account "$NetBios\$ggdiscipline"`
             -AccessRights ReadAndExecute,Write -AppliesTo ThisFolderOnly
            Add-NTFSAccess -Path $disciplineDirectory -Account "$NetBios\$ggdiscipline"`
             -AccessRights ReadAndExecute -AppliesTo ThisFolderSubfoldersAndFiles
            Add-NTFSAccess -Path $disciplineDirectory -Account "CREATOR OWNER"`
             -AccessRights Modify -AppliesTo SubfoldersAndFilesOnly     
        }
#########
# IF the user is a member of administrative team
#########
    } else {
        $ouPath = "OU=$($OUNames[2]),$adrarOUDN"
        Try { Move-ADObject -Identity "CN=$Name,CN=Users,$DomainDN" -TargetPath $ouPath }
        Catch { Write-Host "User $Name does not exist in Users OU" -ForegroundColor Yellow}
        $adminDirectory      = "$($mainDirectories[3])\$Name"
        if (!(Test-Path $adminDirectory)) {
            New-Item -ItemType Directory -Path $adminDirectory > $null
            Write-Host "$adminDirectory has beed created." -ForegroundColor Green
            Clear-NTFSAccess -Path $adminDirectory -DisableInheritance
            Add-NTFSAccess -Path $adminDirectory -Account "$NetBios\domain admins"`
             -AccessRights "FullControl"
            Add-NTFSAccess -Path $adminDirectory -Account "$NetBios\$Name"`
             -AccessRights "Modify"
        } else {
            Write-Host "$adminDirectory already exist!" -ForegroundColor Yellow
        }
    }

    if ($usertype -eq "student") {
        $group = $ggCohort
    } elseif ($usertype -eq "teacher") {
        $group = $ggdiscipline
    } else {
        $group = "gg-$($OUNames[2])"
    }

    $isMember = Get-ADGroupMember -Identity $group | Where-Object {$_.SamAccountName -eq $Name}
    if (!($isMember)) {
        Add-ADGroupMember -Identity $group -Members $Name
        Write-Host "New user $Name has been added to the group $group"`
        -ForegroundColor Blue
    } else {
        Write-Host "User $name is aleady a member of the group $group"`
        -ForegroundColor Yellow
    }
}
#################################################
######      *** End of the script ***      ######
#################################################
