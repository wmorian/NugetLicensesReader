param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Solution,
    [string]$Output
)

if (!(Test-Path $Solution)) {
    Write-Error "Invalid path: $Solution"
    Exit
}

$solutionPath = Resolve-Path $Solution  
if (-Not [System.IO.Path]::GetExtension($solutionPath) -eq ".sln") {
    Write-Error "Please provide the full path of the solution"
    Exit
}

function GetLicenses {
    param (
        $packages
    )
    
    $hash = [ordered]@{ }

    foreach ($package in $packages.GetEnumerator()) {
        $packageName = $package.Name.ToLower()
        $packageVersion = $package.Version
        $nuspecFile = "$env:USERPROFILE\.nuget\packages\$packageName\$packageVersion\$packageName.nuspec"        

        if (!(Test-Path $nuspecFile)) {
            Write-Host "Warning: File not found: $nuspecFile"
            continue
        }

        [xml]$nuspec = Get-Content $nuspecFile

        $data = "" | Select-Object "Name", "Version", "projectUrl", "LicenseUrl"
        $data.Name = $nuspec.package.metadata.id
        $data.Version = $nuspec.package.metadata.version
        $data.projectUrl = $nuspec.package.metadata.projectUrl
        $data.LicenseUrl = $nuspec.package.metadata.licenseUrl
    
        try {
            # $hash.Add($data.Name, $data) 
            $hash.Add($data, 0) 
        }
        catch {
            # Should not happen, because there shouldn't be any duplicate packages anymore at this stage
            Write-Host "Info: ignored duplicate package: $($data.Name, $data.Version)"
        }
    }

    return $hash
}

function GetSubdependencies {
    param (
        $packageName, $packageVersion
    )

    $packageName = $packageName.ToLower()
    $nuspecFile = "$env:USERPROFILE\.nuget\packages\$packageName\$packageVersion\$packageName.nuspec"        

    if (!(Test-Path $nuspecFile)) {
        Write-Host "Warning: File not found and will be ignored: $nuspecFile"
        $uniquePackages.Remove($packageName)
        continue
    }

    [xml]$nuspec = Get-Content $nuspecFile  
    $nuspec.package.metadata.dependencies.group.dependency | ForEach-Object {
        if ($_) {
            $dependency = "" | Select-Object "Name", "Version"
            $dependency.Name = $_.id
            $dependency.Version = $_.version.Trim('[()]')
            $key = "$($dependency.Name):$($dependency.Version)"

            # Doesn't distinguish between same packages with different version numbers, the key should be a KeyValue with name and version
            if (!$uniquePackages.Contains($key)) {
                $uniquePackages.Add($key, $dependency)
                GetSubdependencies $dependency.Name $dependency.Version
            } 
        }
    }
}

$expr = "dotnet list"
$command = "package"
$uniquePackages = [ordered]@{ }


Write-Host "Getting all packages form $solutionPath" 
$packages = [ordered]@{ }
Invoke-Expression "$expr $solutionPath $command" | 
Where-Object { $_ -match ">" } |
ForEach-Object {
    $packageInfo = $_.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
    $dependency = "" | Select-Object "Name", "Version"
    $dependency.Name = $packageInfo[1]
    $dependency.Version = $packageInfo[3].Trim('[()]')

    $key = "$($dependency.Name):$($dependency.Version)"

    if (!$uniquePackages.Contains($key)) {
        $uniquePackages.Add($key, $dependency)
    }
}

# For Logging later
$count = $uniquePackages.Count

# copy the keys in an array, otherwise exception will be thrown during the iteration, because hashtable changes in the loop
$keys = @($uniquePackages.Keys)

Write-Host "Getting all subdependencies..." 
foreach ($key in $keys) {
    $dependency = $uniquePackages[$key]
    GetSubdependencies $dependency.Name $dependency.Version
}

$packages = $uniquePackages.Values | Sort-Object -Property Name

# get licenseUrls for all packages (and subpackages) in solution
$licenses = (GetLicenses $packages) | Sort-Object -Property Name

if ($Output -eq "") {
    $outputPath = [System.IO.Path]::GetDirectoryName($solutionPath)
}
else {
    $outputPath = Resolve-Path $Output
}

# write licenses to file
$licenses.keys | Out-File -FilePath "$outputPath\ThirdPartyLicenses.txt"


# Logging
Write-Host "Direct dependencies found: $count"
Write-Host "Subdependencies found: $($uniquePackages.Count - $count)"
Write-Host "Licenses found: $($licenses.Count)"
Write-Host "Write licenses to $outputPath\ThirdPartyLicenses.txt"
Write-Host "Success"






