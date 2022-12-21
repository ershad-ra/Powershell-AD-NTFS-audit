$events = Get-WinEvent -FilterHashtable @{
    LogName = 'Security'
    Id = 4663,5140
    StartTime = (Get-Date).AddDays(-7)
}

enum AccessType {
    ReadData_ListDirectory = 4416
    WriteData_AddFile = 4417
    AppendData_AddSubdirectory_CreatePipeInstance = 4418
    ReadEA = 4419
    WriteEA = 4420
    Execute_Traverse = 4421
    DeleteChild = 4422
    ReadAttributes = 4423
    WriteAttributes = 4424
    DELETE = 1537
    READ_CONTROL = 1538
    WRITE_DAC = 1539
    WRITE_OWNER = 1540
    SYNCHRONIZE = 1541
    ACCESS_SYS_SEC = 1542
}

$ipCache = @{}
$report = foreach ($event in $events | Sort-Object TimeCreated) {
    [xml]$ex = $event.ToXML()
    $dataHT = @{}
    $ex.Event.EventData.Data | ForEach-Object {$dataHT[$_.Name] = $_.'#text'}
    $ats = foreach ($stringMatch in ($dataHT['AccessList'] | Select-String -Pattern '\%\%(?<id>\d{4})' -AllMatches)) {
    foreach ($group in $stringMatch.Matches.Groups | Where-Object {$_.Name -eq 'id'}) {
            [AccessType]$group.Value
        }
    }
    [pscustomobject]@{
        Time = $event.TimeCreated
        EventId = $event.Id
        LogonID = $dataHT['SubjectLogonId']
        Path = "$($dataHT['ObjectName'])".trim('\??\')
        Share = $dataHT['ShareName']
        User = $dataHT['SubjectUserName']
        UserDomain = $dataHT['SubjectDomainName']
        IpAddress = $dataHT['IpAddress']
        AccessType = $ats -join ', '
    }
    if ($event.Id -eq 5140) {
        $ipCache[$dataHt['SubjectLogonId']] = $dataHt['IpAddress']
    } else {
        $dataHt['IpAddress'] = $ipCache[$dataHt['SubjectLogonId']]
    }
}

$localIps = (Get-NetIPAddress).IPAddress
$report = $report | Where-Object {$_.Share -ne '\\*\IPC$'}
$report = $report | Where-Object {$localIps -notcontains $_.IpAddress}

Install-Module PSHTML

$pathGroup = $report | Group-Object Path | Where-Object {$_.Name}
$shareGroup = $report | Group-Object Share | Where-Object {$_.Name}
$userGroup = $report | Group-Object User | Where-Object {$_.Name}

$html = html {
    header {
        h1 {
            'Share Access Report'
        }
    }
    h2 {
        'Table of contents'
    }
    li {
        'Paths'
        foreach ($pg in $pathGroup) {
            ul {
                a -href "#$($pg.Name)" {
                    $pg.Name
                }
            }
        }
    }
    li {
        'Shares'
        foreach ($sg in $shareGroup) {
            ul {
                a -href "#$($sg.Name)" {
                    $sg.Name
                }
            }
        }
    }
    li {
        'Users'
        foreach ($ug in $userGroup) {
            ul {
                a -href "#$($ug.Name)" {
                    $ug.Name
                }
            }
        }
    }
    foreach ($pg in $pathGroup) {
        h2 -Id $pg.Name {
            $pg.Name
        }
        $pg.Group | ConvertTo-PSHTMLTable -Properties Time,EventId,LogonId,Path,User,UserDomain,IpAddress,AccessType
    }
    foreach ($sg in $shareGroup) {
        h2 -Id $sg.Name {
            $sg.Name
        }
        $sg.Group | ConvertTo-PSHTMLTable -Properties Time,EventId,LogonId,Share,User,UserDomain,IpAddress,AccessType
    }
    foreach ($ug in $userGroup) {
        h2 -Id $ug.Name {
            $ug.Name
        }
        $ug.Group | ConvertTo-PSHTMLTable -Properties Time,EventId,LogonId,Path,User,UserDomain,IpAddress,AccessType
    }
}

$html | Out-File C:\test.html
