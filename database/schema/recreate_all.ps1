# Drop foundation tables and re-apply newTables DDL (see recreate_all.py).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
python (Join-Path $here 'recreate_all.py')
exit $LASTEXITCODE
