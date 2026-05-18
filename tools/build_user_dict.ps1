# Compiles tools/user_gikun.csv into assets/user_dict/user.dic via Docker.
# Run from the project root: pwsh tools/build_user_dict.ps1
$ErrorActionPreference = 'Stop'

docker info *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Error 'Docker Desktop is not running.'
  exit 1
}

$root = Split-Path -Parent $PSScriptRoot
$mountPath = $root -replace '\\', '/'

docker run --rm `
  -v "${mountPath}:/work" `
  -w /work `
  debian:bookworm-slim `
  sh /work/tools/compile_in_docker.sh

Write-Host "user.dic compiled to: $root\assets\user_dict\user.dic"
