Add-Type -AssemblyName System.Drawing
$stream=[IO.File]::Create((Join-Path $PSScriptRoot 'ProxyPanel.ico'))
$writer=New-Object IO.BinaryWriter($stream)
$sizes=@(16,32,48,256);$images=@()
foreach($size in $sizes){
 $bmp=New-Object Drawing.Bitmap($size,$size);$g=[Drawing.Graphics]::FromImage($bmp);$g.SmoothingMode='AntiAlias';$g.Clear([Drawing.Color]::Transparent)
 $scale=$size/64.0;$g.ScaleTransform($scale,$scale)
 $bg=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#123F4B'));$g.FillEllipse($bg,1,1,62,62)
 $pen=New-Object Drawing.Pen([Drawing.ColorTranslator]::FromHtml('#70DDC3'),4)
 $g.DrawLine($pen,20,21,43,32);$g.DrawLine($pen,20,43,43,32)
 $white=New-Object Drawing.SolidBrush([Drawing.Color]::White)
 foreach($point in @(@(20,21),@(20,43),@(43,32))){$g.FillEllipse($white,$point[0]-6,$point[1]-6,12,12)}
 $ms=New-Object IO.MemoryStream;$bmp.Save($ms,[Drawing.Imaging.ImageFormat]::Png);$images+=,$ms.ToArray()
 $ms.Dispose();$g.Dispose();$bmp.Dispose();$bg.Dispose();$pen.Dispose();$white.Dispose()
}
$writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$sizes.Count);$offset=6+16*$sizes.Count
for($i=0;$i -lt $sizes.Count;$i++){$dimension=if($sizes[$i]-eq 256){0}else{$sizes[$i]};$writer.Write([byte]$dimension);$writer.Write([byte]$dimension);$writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$images[$i].Length);$writer.Write([uint32]$offset);$offset+=$images[$i].Length}
foreach($bytes in $images){$writer.Write([byte[]]$bytes)};$writer.Dispose()
