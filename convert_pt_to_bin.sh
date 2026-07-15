#!/bin/bash

# YOLOv8 一键完整转换脚本 (PyTorch -> ONNX -> BIN)
# 自动使用 Docker 完成从 PyTorch 到 BIN 的全流程转换

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $1$(printf '%*s' $((60 - ${#1})) | tr ' ' ' ')║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}→ $1${NC}"
}

# 检查参数
if [ $# -lt 2 ]; then
    print_header "YOLOv8 一键转换脚本"
    echo "使用方式: bash convert_pt_to_bin.sh <pt_model> <calibration_data> [选项]"
    echo ""
    echo "必填参数:"
    echo "  <pt_model>:          PyTorch 模型文件路径"
    echo "  <calibration_data>:  校准数据目录路径"
    echo ""
    echo "可选参数:"
    echo "  --output <dir>       输出目录"
    echo "  --model-size <size>  模型大小 (默认: 640)"
    echo "  --image <name>       Docker 镜像名"
    echo ""
    echo "示例:"
    echo "  bash convert_pt_to_bin.sh yolov8n.pt ./calibration_data"
    echo "  bash convert_pt_to_bin.sh yolov8n.pt ./calibration_data --output ./models"
    echo ""
    exit 1
fi

PT_MODEL="$1"
CALIB_DATA="$2"
OUTPUT_DIR=""
MODEL_SIZE=640
DOCKER_IMAGE="openexplorer/ai_toolchain_ubuntu_20_x5_cpu:v1.2.8"

# 解析可选参数
shift 2
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --model-size)
            MODEL_SIZE="$2"
            shift 2
            ;;
        --image)
            DOCKER_IMAGE="$2"
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# ============================================================
# 第 1 步: 验证输入参数
# ============================================================

print_header "验证输入参数"

# 检查 PyTorch 模型
if [ ! -f "$PT_MODEL" ]; then
    print_error "找不到 PyTorch 模型: $PT_MODEL"
fi
PT_MODEL=$(cd "$(dirname "$PT_MODEL")" && pwd)/$(basename "$PT_MODEL")
print_success "PyTorch 模型: $PT_MODEL"

# 检查校准数据
if [ ! -d "$CALIB_DATA" ]; then
    print_error "找不到校准数据目录: $CALIB_DATA"
fi
CALIB_DATA=$(cd "$CALIB_DATA" && pwd)

IMG_COUNT=$(find "$CALIB_DATA" -iname "*.jpg" -o -iname "*.png" | wc -l)
if [ $IMG_COUNT -eq 0 ]; then
    print_error "校准数据目录中没有图像文件: $CALIB_DATA"
fi
print_success "校准数据: $CALIB_DATA ($IMG_COUNT 张图像)"

# 设置输出目录
if [ -z "$OUTPUT_DIR" ]; then
    DATE=$(date +%Y%m%d_%H%M%S)
    MODEL_BASE=$(basename "$PT_MODEL" .pt)
    OUTPUT_DIR="./converted_models/${DATE}_${MODEL_BASE}"
fi
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
print_success "输出目录: $OUTPUT_DIR"

print_success "模型大小: ${MODEL_SIZE}x${MODEL_SIZE}"

# ============================================================
# 第 2 步: 在 Linux 上进行 ONNX 导出
# ============================================================

print_header "第 1 步: PyTorch -> ONNX 导出 (Linux)"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONVERTER_SCRIPT="$SCRIPT_DIR/yolo_converter.py"

if [ ! -f "$CONVERTER_SCRIPT" ]; then
    print_error "找不到转换脚本: $CONVERTER_SCRIPT"
fi

print_info "运行 ONNX 导出..."
echo ""

python3 "$CONVERTER_SCRIPT" \
    --pt "$PT_MODEL" \
    --cal-data "$CALIB_DATA" \
    --output "$OUTPUT_DIR" \
    --model-size $MODEL_SIZE

if [ $? -ne 0 ]; then
    print_error "ONNX 导出失败"
fi

# 检查 ONNX 文件
ONNX_FILE=$(find "$OUTPUT_DIR" -name "*.onnx" -type f | head -1)
if [ -z "$ONNX_FILE" ]; then
    print_error "ONNX 文件未生成"
fi

print_success "ONNX 导出完成: $(basename $ONNX_FILE)"

# ============================================================
# 第 3 步: 检查 Docker
# ============================================================

print_header "第 2 步: Docker 环境检查"

if ! command -v docker &> /dev/null; then
    print_error "Docker 未安装"
fi

print_success "Docker 已安装: $(docker --version)"

# 检查 Docker daemon
if ! docker info --format "{{.OperatingSystem}}" &> /dev/null; then
    print_error "Docker daemon 未运行"
fi

print_success "Docker daemon 正在运行"

# 检查镜像
print_info "检查 Docker 镜像: $DOCKER_IMAGE"
if ! docker images --quiet "$DOCKER_IMAGE" &> /dev/null; then
    print_warning "镜像不存在，将自动下载..."
    echo ""
    docker pull "$DOCKER_IMAGE"
    if [ $? -ne 0 ]; then
        print_error "镜像下载失败"
    fi
fi

print_success "Docker 镜像已就绪: $DOCKER_IMAGE"

# ============================================================
# 第 4 步: 在 Docker 中进行完整编译
# ============================================================

print_header "第 3 步: Docker 内编译 (ONNX -> BIN)"

# 创建 Docker 内执行的脚本
DOCKER_SCRIPT="$OUTPUT_DIR/compile.sh"
cat > "$DOCKER_SCRIPT" << 'DOCKER_SCRIPT_EOF'
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
if [ $? -ne 0 ]; then
    echo "Configuration check failed"
    exit 1
fi

# 步骤 3: 编译 BIN 模型
echo ""
echo "Running hb_mapper makertbin (this may take a few minutes)..."
hb_mapper makertbin --config config.yaml
if [ $? -ne 0 ]; then
    echo "Model compilation failed"
    exit 1
fi

# 步骤 4: 验证结果
echo ""
echo "Verifying compilation results..."
BIN_FILES=($(find . -name "*.bin" -type f))
if [ ${#BIN_FILES[@]} -eq 0 ]; then
    echo "ERROR: No BIN file generated"
    exit 1
fi

BIN_FILE="${BIN_FILES[0]}"
echo "✓ BIN file generated: $BIN_FILE"
ls -lh "$BIN_FILE"

# 步骤 5: 获取模型信息
echo ""
echo "Model information:"
hrt_model_exec model_info --model_file "$BIN_FILE"

echo ""
echo "✓ Compilation completed successfully!"
exit 0
DOCKER_SCRIPT_EOF

chmod +x "$DOCKER_SCRIPT"

# 运行 Docker 容器
print_info "启动 Docker 容器..."
echo ""

docker run --rm -it \
    -v "$OUTPUT_DIR:/workspace" \
    "$DOCKER_IMAGE" \
    bash /workspace/compile.sh

if [ $? -ne 0 ]; then
    print_error "Docker 编译过程失败"
fi

# ============================================================
# 第 5 步: 验证结果
# ============================================================

print_header "第 4 步: 验证编译结果"

BIN_FILE=$(find "$OUTPUT_DIR" -name "*.bin" -type f | head -1)
if [ -z "$BIN_FILE" ]; then
    print_error "未找到 BIN 文件"
fi

BIN_SIZE=$(du -h "$BIN_FILE" | cut -f1)

print_success "BIN 模型生成成功！"
echo ""
echo "📁 文件信息:"
echo "   名称: $(basename $BIN_FILE)"
echo "   大小: $BIN_SIZE"
echo "   路径: $BIN_FILE"
echo ""

# ============================================================
# 完成
# ============================================================

print_header "✅ 转换完成！"

echo ""
echo -e "${GREEN}转换结果总结:${NC}"
echo ""

for file in "$OUTPUT_DIR"/*; do
    if [ -f "$file" ]; then
        FILENAME=$(basename "$file")
        FILESIZE=$(du -h "$file" | cut -f1)
        
        if [[ "$FILENAME" == *.bin ]]; then
            echo -e "${GREEN}  ✅ $FILENAME${NC} ($FILESIZE) - 部署模型"
        elif [[ "$FILENAME" == *.onnx ]]; then
            echo -e "${GREEN}  ✅ $FILENAME${NC} ($FILESIZE) - ONNX 模型"
        else
            echo "  • $FILENAME ($FILESIZE)"
        fi
    fi
done

echo ""
echo -e "${GREEN}📁 输出目录: $OUTPUT_DIR${NC}"
echo ""
echo -e "${GREEN}🚀 下一步:${NC}"
echo "   1. BIN 模型已生成，可直接在 RDK X5 设备上使用"
echo "   2. 参考 samples/vision/ultralytics_yolo/runtime/ 进行推理测试"
echo "   3. 如需调整量化参数，修改 config.yaml 后重新运行此脚本"
echo ""

print_success "一键转换完成！"
