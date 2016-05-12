$ComputerName = "STGGXDISTSQL01";

Write-Output ""
Write-Output "For 1024k offset, should return 1048576 on index 0 for all data and log disks";
Get-WmiObject -Query "SELECT Name, Index, BlockSize, StartingOffset FROM Win32_DiskPartition WHERE Index = 0" -ComputerName $ComputerName | Select-Object Name, Index, BlockSize, StartingOffset | ft

Write-Output ""
Write-Output "For 64K allocation unit, should return 65536 for all data and log drives";
Get-WmiObject -Query "SELECT DriveLetter, BlockSize FROM Win32_Volume WHERE FileSystem='NTFS' AND DriveLetter > 1" -ComputerName $ComputerName | Select-Object DriveLetter, BlockSize | ft

