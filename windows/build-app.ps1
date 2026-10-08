# 构建 Windows 版 Coding Plan Monitor（单文件自包含 EXE）
# 用法：在 Windows 上安装 .NET 8 SDK 后，于本目录执行：powershell -File build-app.ps1
$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot
try {
    dotnet publish .\CodingPlanMonitor\CodingPlanMonitor.csproj `
        -c Release -r win-x64 --self-contained true `
        -p:PublishSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true `
        -o .\artifacts
    Write-Host ""
    Write-Host "构建完成：$PSScriptRoot\artifacts\CodingPlanMonitor.exe" -ForegroundColor Green
    Write-Host "双击运行即可，图标会出现在系统托盘（通知区域）。"
} finally {
    Pop-Location
}
