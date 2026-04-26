# Run all seed scripts in order (see seed_all.py).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
python (Join-Path $here 'seed_all.py')
exit $LASTEXITCODE
