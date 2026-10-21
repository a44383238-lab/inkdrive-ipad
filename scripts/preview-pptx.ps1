param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Relative)
$ErrorActionPreference='Stop'
$base=(Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
$source=[IO.Path]::GetFullPath((Join-Path $base $Relative))
if(-not $source.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($source) -ne '.pptx'){throw 'Invalid presentation path'}
$sha=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
$out=Join-Path $base ".inkdrive\previews\$sha"
if(Test-Path -LiteralPath (Join-Path $out 'manifest.json')){return}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($source)
try{
  function Read-Entry([string]$name){$entry=$zip.GetEntry($name);if($null -eq $entry -or $entry.Length -gt 5000000){throw 'Invalid PPTX metadata'};$reader=[IO.StreamReader]::new($entry.Open());try{$reader.ReadToEnd()}finally{$reader.Dispose()}}
  [xml]$presentation=Read-Entry 'ppt/presentation.xml'
  $ns=[Xml.XmlNamespaceManager]::new($presentation.NameTable);$ns.AddNamespace('p','http://schemas.openxmlformats.org/presentationml/2006/main')
  $size=$presentation.SelectSingleNode('//p:sldSz',$ns)
  $width=[long]$size.cx;$height=[long]$size.cy
  if($width -le 0 -or $height -le 0){throw 'Invalid slide size'}
  $slides=@($presentation.SelectNodes('//p:sldId',$ns)|ForEach-Object{ @{slideId=$_.id;relationship=$_.GetAttribute('id','http://schemas.openxmlformats.org/officeDocument/2006/relationships')} })
}finally{$zip.Dispose()}
New-Item -ItemType Directory -Path $out -Force | Out-Null
$registry=Join-Path $base '.inkdrive\presentations'
New-Item -ItemType Directory -Path $registry -Force | Out-Null
$hasher=[Security.Cryptography.SHA256]::Create()
$pathHash=([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($Relative)))).Replace('-','').ToLowerInvariant()
$record=Join-Path $registry ($pathHash+'.json')
$documentId=[guid]::NewGuid().ToString()
if(Test-Path -LiteralPath $record){$documentId=(Get-Content -LiteralPath $record -Raw|ConvertFrom-Json).documentId}
[IO.File]::WriteAllText($record,(@{documentId=$documentId;path=$Relative;sourceSHA256=$sha}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$pageIDs=@($slides|ForEach-Object{$bytes=$hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($documentId+':'+$_.slideId));[guid]::new([byte[]]$bytes[0..15]).ToString()})
$hasher.Dispose()
$powerpoint=$null;$deck=$null
try{
  $powerpoint=New-Object -ComObject PowerPoint.Application
  $powerpoint.AutomationSecurity=3
  $deck=$powerpoint.Presentations.Open($source,$true,$false,$false)
  $temporary=Join-Path $out ('preview-'+[guid]::NewGuid().ToString()+'.pdf')
  $deck.SaveAs($temporary,32)
  if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha){throw 'Source changed during preview'}
  $target=Join-Path $out 'preview.pdf'
  if(-not(Test-Path -LiteralPath $target)){Move-Item -LiteralPath $temporary -Destination $target}
  $manifest=@{format='inkdrive.preview';version=1;kind='pptx';documentId=$documentId;pageIDs=$pageIDs;sourceSHA256=$sha;widthEMU=$width;heightEMU=$height;slides=$slides;preview='preview.pdf';previewSHA256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()}
  [IO.File]::WriteAllText((Join-Path $out 'manifest.json'),($manifest|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}finally{
  if($null -ne $deck){$deck.Close();[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($deck)}
  if($null -ne $powerpoint){$powerpoint.Quit();[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($powerpoint)}
}
