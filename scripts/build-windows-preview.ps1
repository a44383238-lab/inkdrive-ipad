param([Parameter(Mandatory=$true)][string]$WebView2Package, [Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$package = (Resolve-Path -LiteralPath $WebView2Package).Path
$out = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $out -Force | Out-Null
$wpf = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\WPF'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$refs = @("/r:$package\lib\net462\Microsoft.Web.WebView2.Core.dll", "/r:$package\lib\net462\Microsoft.Web.WebView2.Wpf.dll",
  "/r:$wpf\PresentationFramework.dll", "/r:$wpf\PresentationCore.dll", "/r:$wpf\WindowsBase.dll", '/r:System.Xaml.dll', '/r:System.Net.Http.dll', '/r:System.Windows.Forms.dll', '/r:System.Web.Extensions.dll')
& $compiler /nologo /target:winexe /platform:x64 "/out:$out\InkDrive.exe" "/win32manifest:$repo\windows\native\app.manifest" @refs "$repo\windows\native\App.cs"
if ($LASTEXITCODE -ne 0) { throw 'Windows preview compilation failed' }
Copy-Item -LiteralPath "$package\lib\net462\Microsoft.Web.WebView2.Core.dll", "$package\lib\net462\Microsoft.Web.WebView2.Wpf.dll", "$package\runtimes\win-x64\native\WebView2Loader.dll" -Destination $out -Force
Copy-Item -LiteralPath "$package\LICENSE.txt" -Destination (Join-Path $out 'WebView2-LICENSE.txt') -Force
Copy-Item -LiteralPath "$package\NOTICE.txt" -Destination (Join-Path $out 'WebView2-NOTICE.txt') -Force
$reference = Join-Path $out 'windows\reference'
New-Item -ItemType Directory -Path $reference, (Join-Path $out 'shared') -Force | Out-Null
Get-ChildItem -LiteralPath "$repo\windows\reference" | Copy-Item -Destination $reference -Recurse -Force
Get-ChildItem -LiteralPath "$repo\shared" | Copy-Item -Destination (Join-Path $out 'shared') -Force
New-Item -ItemType Directory -Path (Join-Path $out 'scripts'),(Join-Path $out 'src'),(Join-Path $out 'config'),(Join-Path $out 'work') -Force | Out-Null
Get-ChildItem -LiteralPath "$repo\scripts" | Copy-Item -Destination (Join-Path $out 'scripts') -Recurse -Force
Copy-Item -LiteralPath "$repo\src\domain.mjs" -Destination (Join-Path $out 'src') -Force
if(Test-Path -LiteralPath "$repo\config\runtime.local.json"){Copy-Item -LiteralPath "$repo\config\runtime.local.json" -Destination (Join-Path $out 'config') -Force}
[IO.File]::WriteAllText((Join-Path $out 'InkDrive.exe.config'), '<?xml version="1.0"?><configuration><startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8"/></startup></configuration>')
[IO.File]::WriteAllText((Join-Path $out '읽어주세요.txt'), "InkDrive 2 Windows`r`nInkDrive.exe 실행 → 폴더 연결 → iCloud의 InkDrive 폴더를 선택하세요.`r`n학교 탭에서 로그인 후 지금 확인을 누르세요. 앱이 켜져 있으면 30분마다 확인합니다.`r`nPPTX 원본은 유지하며 PowerPoint가 있는 PC에서 미리보기를 생성합니다. iPad에서는 기본 미리보기도 사용합니다.`r`n수업 정리 버튼은 기존 ChatGPT 로그인/로컬 전사 실행기를 사용합니다. 앱이 켜져 있으면 밤 10시에 실행합니다.`r`nNode.js/.NET Framework 4.8/WebView2 Runtime이 필요합니다. PDF 필기 편집은 iPad에서 진행합니다.")
Write-Output (Join-Path $out 'InkDrive.exe')
