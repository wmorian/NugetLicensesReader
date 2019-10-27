# NugetLicensesReader
Reads all License URLs from every dependency and subdependency of a solution

## Requirements
It is necessary to install *dotnet cli* globaly before running this script, because the direct dependencies are read with the `dotnet list <sln> package` command. 

## How to use
Just call the script and provide the full name of the solution (relative or absolute). The output path is optional. If no output is provided, the directory of the solution is assumed.

`./GetLicenses.ps1 [path/to/solution.sln]`

or

`./GetLicenses.ps1 [path/to/solution.sln] [path/to/output]`
