@echo off
REM 一键 PyTorch 到 BIN 模型转换脚本
REM 自动完成 ONNX 导出和 Docker 编译全流程

setlocal enabledelayedexpansion

color 0A
cls

echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║          YOLOv8 一键转换脚本: PyTorch -^> BIN                 ║
echo ║                                                                ║
echo ║  支持完整的自动转换流程:                                       ║
echo ║  1. PyTorch (.pt) -^> ONNX (.onnx)                            ║
echo ║  2. ONNX -^> BPU BIN (.bin) via Docker                        ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.

REM 检查参数
if "%~1"=="" (
    echo 使用方式: convert_pt_to_bin.bat ^<pt_model^> ^<calibration_data^>
    echo.
    echo 参数说明:
    echo   ^<pt_model^>:          PyTorch 模型文件路径 (.pt 文件)
    echo   ^<calibration_data^>:  校准数据目录路径 (包含 jpg/png 图像)
    echo.
    echo 可选参数:
    echo   --output ^<dir^>       输出目录 (默认: ./converted_models/^<date^>_^<name^>)
    echo   --model-size ^<size^>  模型大小 (默认: 640, 支持: 640/1280)
    echo   --image ^<name^>       Docker 镜像名 (默认: openexplorer/ai_toolchain_ubuntu_20_x5_cpu:v1.2.8)
    echo.
    echo 示例:
    echo   convert_pt_to_bin.bat yolov8n.pt calibration_data
    echo   convert_pt_to_bin.bat yolov8n.pt calibration_data --output ./my_models
    echo   convert_pt_to_bin.bat yolov8n.pt calibration_data --model-size 1280
    echo.
    pause
    exit /b 1
)

if "%~2"=="" (
    echo 错误: 缺少校准数据参数
    echo 使用: convert_pt_to_bin.bat ^<pt_model^> ^<calibration_data^>
    pause
    exit /b 1
)

set "PT_MODEL=%~1"
set "CALIB_DATA=%~2"
set "OUTPUT_DIR="
set "MODEL_SIZE=640"
set "DOCKER_IMAGE=openexplorer/ai_toolchain_ubuntu_20_x5_cpu:v1.2.8"

REM 解析可选参数
shift
shift
:parse_options
if not "%~1"=="" (
    if "%~1"=="--output" (
        set "OUTPUT_DIR=%~2"
        shift
        shift
        goto parse_options
    )
    if "%~1"=="--model-size" (
        set "MODEL_SIZE=%~2"
        shift
        shift
        goto parse_options
    )
    if "%~1"=="--image" (
        set "DOCKER_IMAGE=%~2"
        shift
        shift
        goto parse_options
    )
    shift
    goto parse_options
)

REM 检查文件
if not exist "!PT_MODEL!" (
    color 0C
    echo.
    echo ❌ 错误: 找不到 PyTorch 模型文件
    echo    路径: !PT_MODEL!
    echo.
    pause
    exit /b 1
)

if not exist "!CALIB_DATA!" (
    color 0C
    echo.
    echo ❌ 错误: 找不到校准数据目录
    echo    路径: !CALIB_DATA!
    echo.
    pause
    exit /b 1
)

REM 检查 PowerShell
powershell -NoProfile -Command "exit 0" >nul 2>&1
if errorlevel 1 (
    color 0C
    echo.
    echo ❌ 错误: PowerShell 不可用
    echo.
    pause
    exit /b 1
)

REM 构建 PowerShell 命令
if "!OUTPUT_DIR!"=="" (
    set "PS_CMD=.\convert_pt_to_bin.ps1 -PtModel '!PT_MODEL!' -CalibrationData '!CALIB_DATA!' -ModelSize !MODEL_SIZE! -DockerImage '!DOCKER_IMAGE!'"
) else (
    set "PS_CMD=.\convert_pt_to_bin.ps1 -PtModel '!PT_MODEL!' -CalibrationData '!CALIB_DATA!' -OutputDir '!OUTPUT_DIR!' -ModelSize !MODEL_SIZE! -DockerImage '!DOCKER_IMAGE!'"
)

REM 运行 PowerShell 脚本
echo.
color 0A
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { !PS_CMD! }"

if errorlevel 1 (
    color 0C
    echo.
    echo ❌ 转换失败
    echo.
    pause
    exit /b 1
)

color 0A
echo.
echo ✅ 转换成功！
echo.
pause
exit /b 0
