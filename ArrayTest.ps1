$Script:ArrayTest = @()

$Folders = gci /users/tim

Foreach ($Folder in $Folders)
{
    $NewArray += "Folder name: $($Folder.Name) - Folder Size: $($Folder.Length)`n"
}

Write-Host "Dump out new array:"
$NewArray