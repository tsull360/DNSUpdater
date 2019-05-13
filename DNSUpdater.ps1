<#
.SYNOPSIS

    Script for automating the registration and updating of 'synthetic' records in Google DNS

.DESCRIPTION

    This script, DNSUpdater.ps1, automates the management of DNS records contained in
    an Google DNS zone. Begins by reading a local data file, retrieves available records
    from Google, and performs needed actions (Create, Update or Delete) based on the 
    contents of the input file.

.PARAMETER Zonename

    Google DNS zone name to work against.

.PARAMETER ResGroup

    Google Resource Group name.

.PARAMETER RecordFile

    Path to csv file that holds the records for the domain.

.PARAMETER ConnectionFile

    Path to csv file that contains the parameters needed for connecting to Google.

.PARAMETER Whatif

    Enables the script to run without performing actual changes to Google DNS

.PARAMETER Email
    Boolean value indicating if an email should be sent

.PARAMETER MailSend
    Recipient of mail message

.PARAMETER MailFrom
    Sender of mail message

.PARAMETER MailServer
    Address of mail server

.NOTES

    Author: Tim Sullivan
    Version: 1.0
    Date: 27/12/2016
    Name: DNSUpdater.ps1

.EXAMPLE

    DNSUpdates.ps1 -Zonename contoso.com -ResGroup GoogleDNSResourceGroup -RecordFile ContosoDNS.csv -ConnectionFile ContosoConnection.csv -whatif

    This example will perform updates against the contoso.com domain contained in 
    the 'GoogleDNSResourceGroup' using the DNS records in 'ContosoDNS.csv' as the authoritative data
    for the domain. The 'ContosoConnection' file has the needed security info for connecting to the
    resource. 
#>

Param
(
[String]$ZoneName = "nativemode.com",
[String]$RecordFile = ".\NativemodeRecords.csv",
[Boolean]$Mail,
[String]$MailFrom,
[String]$MailTo,
[String]$MailServer
)

Write-Host "Supplied Values"
Write-Host "Zone: "$Zonename
Write-Host "Record File: "$RecordFile

$Script:UpdateResults = @()
$Script:TestResults = @()

#This function queries a public resource to return the external IP address at the current
#location.
Function Get-PublicIP
{
    try
    {
        $Script:PublicIP = (Invoke-WebRequest -UseBasicParsing https://domains.google.com/checkip).content
        Write-Host "Public IP: $PublicIP"
    }
    catch
    {
        Write-Host "Error getting pulbic IP. Error: "$_.Exception.Message
    }

}

#This function queries DNS to get the current result
Function Get-Record($QueryRecord)
{
    try 
    {
        $Script:QueryResult = (Resolve-DnsName -Server 8.8.8.8 -Name $QueryRecord).IPAddress
        
    }
    catch 
    {
        $Script:QueryResult = "Record not found!"
    }
}

#This function updates a record that already exists in the identified zone.
Function Update-Record ($RecordName, $RecordUserName, $RecordPassword, $RecordRecord, $ZoneName, $RecordToSet)
{
    Write-Host "Record Name: $RecordName"
    Write-Host "Record To Set: $RecordToSet"
    $Creds = "$($RecordUserName):$($RecordPassword)"
    #encode the username and password for the header
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Creds)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $basicAuthValue = "Basic $base64"
    $headers = @{ Authorization =  $basicAuthValue }

    $url = "https://domains.google.com/nic/update?hostname=$RecordName.$ZoneName&myip=$RecordToSet"
    Write-Host "URL being used: $URL"
    try 
    {
        Write-Host "Updating record..."
        $Response = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing 
        
        switch -Wildcard ($Response.Content)
        {
        "good*" {Write-Host "The update was successful!" $Result = "Good" -ForegroundColor Green}
        "nochg*" {Write-Host "The supplied IP address $RecordToSet is already set for this host." $Result = "No Change" -ForegroundColor Green}
        "nohost*" {Write-Warning "The hostname does not exist, or does not have Dynamic DNS enabled. `nHostname: $hostname" $Result = "Missing Host"}
        "badauth*" {Write-Warning "The username / password combination is not valid for the specified host! `nUsername: $user`nPassword: $pwd" $Result = "Bad Auth"}
        "notfqdn*" {Write-Warning "The supplied hostname is not a valid fully-qualified domain name! `nHostname: $hostname" $Result = "Bad Hostname"}
        "badagent*" {Write-Warning "Your Dynamic DNS client is making bad requests. Ensure the user agent is set in the request, and that you are only attempting to set an IPv4 address. IPv6 is not supported." $Result = "Bad Request"}
        "abuse*" {Write-Warning "Dynamic DNS access for the hostname has been blocked due to failure to interpret previous responses correctly." $Result = "Blocked"}
        "911*" {Write-Warning "An error happened on our end. Wait 5 minutes and retry." $Result = "Retry in 5 Mintues"}
        }
        
        $UpdateResults += "Record: $RecordName.$ZoneName Value: $RecordToSet Result: $Result`n"
    }
    catch 
    {
        Write-Host "Error updating record. Error:" $_.Exception.Message
        $UpdateResults += "Record: $RecordName.$ZoneName Result: $($_.Exception.Message)`n"
    }

}

# This function logs the actions taken to the local Event Viewer
Function Write-Work ($MessageBody)
{
    #Create event log source, if it does not already exist.
    if ([System.Diagnostics.EventLog]::SourceExists("DNSManager") -eq $false) 
    {
        [System.Diagnostics.EventLog]::CreateEventSource("DNSManager","Application")
    }

    Write-EventLog -LogName "Application" -EntryType "Information" -EventId 1024 -Source DNSManager -Message $MessageBody

}

Write-Host "---------------------"
Write-Host "Trying to get network Public IP address"
Get-PublicIP($PublicIP)

#Import configuration file
try {
    $Records = Import-Csv -Path $RecordFile
    Write-Host "--------------------------"
    Write-Host "Attempting to get record info"
    ForEach ($Record in $Records)
    {
        $RecordName = $Record.Record
        $RecordData = $Record.Data
        $RecordUsername = $Record.UserName
        $RecordPassword = $Record.Password
        Write-Host "Record Info"

        Write-Host "Record: $RecordName"
        Write-Host "Data: $RecordData"
        Write-Host "Username: $RecordUsername"
        Write-Host "Password: $RecordPassword"
        Write-Host "Checking existing value vs desired value..."
        try 
        {
            $QueryRecord = "$Recordname.$ZoneName"
            Write-Host "Value to query: $QueryRecord"
            Get-Record($QueryRecord)
            
            Write-Host "Resolution result: $QueryResult"
                
        }
        catch 
        {
            Write-Host "Error getting record. Error: "$_.Exception.Message    
        }

        # Code below evaluates data file to see if record should use the public IP of the network,
        # or a value specified in the data file.
        Write-Host "Checking record data to see if it should be set to current public IP address"
        If ($Record.Data -like "Public")
        {
            Write-Host "Record set to be public IP."
            $RecordToSet = $PublicIP
        }
        else 
        {
            Write-Host "Record set to be specific IP."
            $RecordToSet = $Record.Data    
        }

        # Check to see if further work needs to be done. Query record, see if response equals intended
        # value
        If ($RecordToSet -like $QueryResult)
        {   
            Write-Host "Record to set and current value are equal. Nothing more to do."
            Write-Host "Record to set value: $RecordToSet"
            Write-Host "Current value: $QueryResult"
            $Update = $false
            $UpdateResults += "Record: $RecordName.$ZoneName Status: No update required`n"

        }
        else 
        {
            Write-Host "Record needs to be updated."
            Write-Host "Record to set value: $RecordToSet"
            Write-Host "Current value: $QueryResult"
            $Update = $true

        }
        If ($Update -eq $true)
        {
            Write-Host "Calling update record function."
            Update-Record $RecordName $RecordUserName $RecordPassword $RecordRecord $ZoneName $RecordToSet
        }
        Write-Host "----------------------"
        Write-Host ""
    }
}
catch {
    Write-Host "Error getting data file. Error: "$_.Exception.Message
}

Write-Host "Update $UpdateResults"

If ($Mail -eq $true)
{
$MessageBody = @"
Google Dynamic DNS Update Script
Version: 1.1

Supplied Values
Zone Name: $ZoneName
Record File: $RecordFile

Record Update Status
$UpdateResults

End of DNS Update Script

"@

    #Will send notification message to identified reciever.
    Send-MailMessage -From $MailFrom -To $MailTo -SmtpServer $MailServer -Subject "DNS Update Status Message" -Body $MessageBody
}

Write-Work $MessageBody