#!/usr/bin/env pwsh
# YOLOv8 一键完整转换脚本 (PyTorch -> ONNX -> BIN)
# 自动使用 Docker 完成从 PyTorch 到 BIN 的全流程转换

param(
    [Parameter(Mandatory=$true)]
    [string]$PtModel,
    
    [Parameter(Mandatory=$true)]
    [string]$CalibrationData,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputDir = $null,
    
    [Parameter(Mandatory=$false)]
    [int]$ModelSize = 640,
    
    [Parameter(Mandatory=$false)]
    [string]$DockerImage = "openexplorer/ai_toolchain_ubuntu_20_x5_cpu:v1.2.8"
)

# 颜色定义
$Green = "`e[32m"
$Red = "`e[31m"
$Yellow = "`e[33m"
$Blue = "`e[34m"
$Reset = "`e[0m"

function Print-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "$Blue╔" + ("═" * 58) + "╗$Reset"
    Write-Host "$Blue║  $Text" + (" " * (54 - $Text.Length)) + "║$Reset"
    Write-Host "$Blue╚" + ("═" * 58) + "╝$Reset"
    Write-Host ""
}

function Print-Success {
    param([string]$Text)
    Write-Host "$Green✓ $Text$Reset"
}

function Print-Error {
    param([string]$Text)
    Write-Host "$Red❌ $Text$Reset"
    exit 1
}

function Print-Warning {
    param([string]$Text)
    Write-Host "$Yellow⚠️  $Text$Reset"
}

function Print-Info {
    param([string]$Text)
    Write-Host "$Blue→ $Text$Reset"
}

# ============================================================
# 第 1 步: 验证输入参数
# ============================================================

Print-Header "验证输入参数"

# 检查 PyTorch 模型
$PtModel = (Resolve-Path $PtModel -ErrorAction Stop).Path
Print-Success "PyTorch 模型: $PtModel"

# 检查校准数据
$CalibrationData = (Resolve-Path $CalibrationData -ErrorAction Stop).Path
$imgCount = @(Get-ChildItem -Path $CalibrationData -Include "*.jpg", "*.png" -Recurse -ErrorAction SilentlyContinue).Count
if ($imgCount -eq 0) {
    Print-Error "校准数据目录中没有图像文件: $CalibrationData"
}
Print-Success "校准数据: $CalibrationData ($imgCount 张图像)"

# 设置输出目录
if (-not $OutputDir) {
    $date = Get-Date -Format "yyyyMMdd_HHmmss"
    $modelBaseName = [System.IO.Path]::GetFileNameWithoutExtension($PtModel)
    $OutputDir = Join-Path $PSScriptRoot "converted_models" "${date}_${modelBaseName}"
}

$OutputDir = (New-Item -ItemType Directory -Path $OutputDir -Force).FullName
Print-Success "输出目录: $OutputDir"

Print-Success "模型大小: ${ModelSize}x${ModelSize}"

# ============================================================
# 第 2 步: 在 Windows 上进行 ONNX 导出
# ============================================================

Print-Header "第 1 步: PyTorch -> ONNX 导出 (Windows)"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$converterScript = Join-Path $scriptDir "yolo_converter.py"

if (-not (Test-Path $converterScript)) {
    Print-Error "找不到转换脚本: $converterScript"
}

Print-Info "运行 ONNX 导出..."
Write-Host ""

$pythonCmd = @(
    $converterScript,
    "--pt", $PtModel,
    "--cal-data", $CalibrationData,
    "--output", $OutputDir,
    "--model-size", $ModelSize
)

python @pythonCmd

if ($LASTEXITCODE -ne 0) {
    Print-Error "ONNX 导出失败"
}

# 检查 ONNX 文件
$onnxFile = Join-Path $OutputDir "*.onnx"
$onnxFiles = @(Get-ChildItem -Path $onnxFile -ErrorAction SilentlyContinue)

if ($onnxFiles.Count -eq 0) {
    Print-Error "ONNX 文件未生成"
}

$onnxFile = $onnxFiles[0].FullName
Print-Success "ONNX 导出完成: $(Split-Path $onnxFile -Leaf)"

# ============================================================
# 第 3 步: 检查 Docker
# ============================================================

Print-Header "第 2 步: Docker 环境检查"

$dockerExe = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerExe) {
    Print-Error "Docker 未安装或不在 PATH 中。请先安装 Docker"
}

Print-Success "Docker 已安装: $($dockerExe.Source)"

# 检查 Docker 是否运行
try {
    docker info --format "{{.OperatingSystem}}" | Out-Null
} catch {
    Print-Error "Docker daemon 未运行。请启动 Docker"
}

Print-Success "Docker daemon 正在运行"

# 检查镜像
Print-Info "检查 Docker 镜像: $DockerImage"
$imageExists = docker images --quiet $DockerImage
if (-not $imageExists) {
    Print-Warning "镜像不存在，将自动下载..."
    Write-Host ""
    docker pull $DockerImage
    if ($LASTEXITCODE -ne 0) {
        Print-Error "镜像下载失败"
    }
}

Print-Success "Docker 镜像已就绪: $DockerImage"

# ============================================================
# 第 4 步: 在 Docker 中进行完整编译
# ============================================================

Print-Header "第 3 步: Docker 内编译 (ONNX -> BIN)"

# 获取 ONNX 文件名
$onnxFileName = Split-Path $onnxFile -Leaf
$modelPrefix = [System.IO.Path]::GetFileNameWithoutExtension($onnxFileName)

# 创建 Docker 内执行的脚本
$dockerScriptContent = @"
#!/bin/bash
set -e

echo "Starting model compilation inside Docker..."

cd /workspace

# 步骤 1: 检查配置文件
echo "Checking config.yaml..."
if [ ! -f config.yaml ]; then
    echo "ERROR: config.yaml not found"
    exit 1
fi

# 步骤 2: 检查配置
echo ""
echo "Running hb_mapper checker..."
hb_mapper checker --model-type onnx --config config.yaml
if [ `$? -ne 0 ]; then
    echo "Configuration check failed"
    exit 1
fi

# 步骤 3: 编译 BIN 模型
echo ""
echo "Running hb_mapper makertbin (this may take a few minutes)..."
hb_mapper makertbin --config config.yaml
if [ `$? -ne 0 ]; then
    echo "Model compilation failed"
    exit 1
fi

# 步骤 4: 验证结果
echo ""
echo "Verifying compilation results..."
BIN_FILES=(\`find . -name "*.bin" -type f\`)
if [ \${#BIN_FILES[@]} -eq 0 ]; then
    echo "ERROR: No BIN file generated"
    exit 1
fi

BIN_FILE=\${BIN_FILES[0]}
echo "✓ BIN file generated: \$BIN_FILE"
ls -lh "\$BIN_FILE"

# 步骤 5: 获取模型信息
echo ""
echo "Model information:"
hrt_model_exec model_info --model_file "\$BIN_FILE"

echo ""
echo "✓ Compilation completed successfully!"
exit 0
"@

$dockerScriptPath = Join-Path $OutputDir "compile.sh"
Set-Content -Path $dockerScriptPath -Value $dockerScriptContent -Encoding UTF8

# 运行 Docker 容器
Print-Info "启动 Docker 容器..."
Write-Host ""

$dockerCmd = @(
    "run",
    "--rm",
    "-it",
    "-v", "$OutputDir`:/workspace",
    $DockerImage,
    "bash", "/workspace/compile.sh"
)

docker @dockerCmd

if ($LASTEXITCODE -ne 0) {
    Print-Error "Docker 编译过程失败"
}

# ============================================================
# 第 5 步: 验证结果
# ============================================================

Print-Header "第 4 步: 验证编译结果"

$binFiles = @(Get-ChildItem -Path $OutputDir -Filter "*.bin" -Recurse -ErrorAction SilentlyContinue)

if ($binFiles.Count -eq 0) {
    Print-Error "未找到 BIN 文件"
}

$binFile = $binFiles[0]
$binSize = $binFile.Length / 1MB

Print-Success "BIN 模型生成成功！"
Write-Host ""
Write-Host "📁 文件信息:"
Write-Host "   名称: $($binFile.Name)"
Write-Host "   大小: $([math]::Round($binSize, 2)) MB"
Write-Host "   路径: $($binFile.FullName)"
Write-Host ""

# ============================================================
# 完成
# ============================================================

Print-Header "✅ 转换完成！"

Write-Host ""
Write-Host "$Green转换结果总结:$Reset"
Write-Host ""

$files = Get-ChildItem -Path $OutputDir -File -ErrorAction SilentlyContinue
foreach ($file in $files) {
    $size = $file.Length / 1MB
    $sizeStr = if ($size -lt 1) { "$([math]::Round($file.Length / 1KB, 2)) KB" } else { "$([math]::Round($size, 2)) MB" }
    
    if ($file.Extension -eq ".bin") {
        Write-Host "$Green  ✅ $($file.Name)$Reset ($sizeStr) - 部署模型"
    } elseif ($file.Extension -eq ".onnx") {
        Write-Host "$Green  ✅ $($file.Name)$Reset ($sizeStr) - ONNX 模型"
    } else {
        Write-Host "  • $($file.Name) ($sizeStr)"
    }
}

Write-Host ""
Write-Host "$Green📁 输出目录: $OutputDir$Reset"
Write-Host ""
Write-Host "$Green🚀 下一步:$Reset"
Write-Host "   1. BIN 模型已生成，可直接在 RDK X5 设备上使用"
Write-Host "   2. 参考 samples/vision/ultralytics_yolo/runtime/ 进行推理测试"
Write-Host "   3. 如需调整量化参数，修改 config.yaml 后重新运行此脚本"
Write-Host ""

Print-Success "一键转换完成！"
