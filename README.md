# 🚀 YOLO 模型转换指南

---

## 📌 项目概况

一键将 YOLO PyTorch 模型 (`.pt`) 转换为 RDK X5 BPU 部署模型 (`.bin`)：

```
PyTorch (.pt) ──→ ONNX (.onnx) ──→ BPU (.bin)
   ① Windows 上导出       ② Docker 内编译
```

**已提供的文件**（都在本项目根目录下）：

| 文件 | 用途 |
|------|------|
| `convert_pt_to_bin.bat` | **Windows 用户入口**（双击或用 cmd 运行） |
| `convert_pt_to_bin.ps1` | **PowerShell 版**（功能最全） |
| `convert_pt_to_bin.sh` | **Linux/macOS 用户入口** |
| `yolo_converter.py` | Python 核心转换引擎 |

---

## 🎯 快速开始

### 方式 1️⃣: Windows 用户（最简单）

```batch
convert_pt_to_bin.bat "C:\path\to\model.pt" "D:\path\to\calibration_data"
```

带参数：
```batch
convert_pt_to_bin.bat "C:\path\to\model.pt" "D:\path\to\calibration_data" ^
    --output "D:\my_models" ^
    --model-size 640
```

### 方式 2️⃣: Linux/macOS 用户

```bash
bash convert_pt_to_bin.sh /path/to/model.pt /path/to/calibration_data
```

### 方式 3️⃣: PowerShell（高级）

```powershell
.\convert_pt_to_bin.ps1 -PtModel "C:\path\to\model.pt" `
    -CalibrationData "D:\path\to\calibration_data" `
    -OutputDir "D:\my_models" `
    -ModelSize 640
```

---

## 📝 参数说明

### 必填参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `<pt_model>` 或 `-PtModel` | PyTorch 模型文件路径 | `yolov8n.pt` 或 `C:\models\number715.pt` |
| `<calibration_data>` 或 `-CalibrationData` | 校准数据目录 | `./calib_data` 或 `D:\calibration_images` |

### 可选参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--output` / `-OutputDir` | 输出目录 | `./converted_models/<date>_<model_name>` |
| `--model-size` / `-ModelSize` | 输入模型大小 | `640` |
| `--image` / `-DockerImage` | Docker 镜像名 | `openexplorer/ai_toolchain_ubuntu_20_x5_cpu:v1.2.8` |

---

## 💡 使用示例

### 示例 1: 基本使用

最简单的用法，使用默认参数：

**Windows:**
```batch
convert_pt_to_bin.bat number715.pt calibration_data
```

**Linux/macOS:**
```bash
bash convert_pt_to_bin.sh number715.pt calibration_data
```

### 示例 2: 自定义输出目录

指定输出目录存储转换结果：

**Windows:**
```batch
convert_pt_to_bin.bat number715.pt calibration_data --output D:\my_converted_models
```

**Linux:**
```bash
bash convert_pt_to_bin.sh number715.pt calibration_data --output ./my_models
```

### 示例 3: 不同的输入大小

转换 1280x1280 的模型：

**Windows:**
```batch
convert_pt_to_bin.bat yolov8l.pt calibration_data --model-size 1280
```

**Linux:**
```bash
bash convert_pt_to_bin.sh yolov8l.pt calibration_data --model-size 1280
```

### 示例 4: 使用自定义 Docker 镜像

如果您有自定义的 Docker 镜像：

**Windows:**
```batch
convert_pt_to_bin.bat model.pt calib --image my-custom-toolchain:v1.0
```

**Linux:**
```bash
bash convert_pt_to_bin.sh model.pt calib --image my-custom-toolchain:v1.0
```

---

## ⏱️ 执行时间预估

| 阶段 | 时间 |
|------|------|
| ONNX 导出 | 2-3 分钟 |
| Docker 启动 | 1-2 分钟 |
| 配置检查 | 1-2 分钟 |
| BIN 编译 | 5-30 分钟 |
| **总计** | **10-40 分钟** |

> ⏱️ 时间取决于模型大小、硬件性能和网络速度

---

## 📊 完整执行流程

```
┌─────────────────────────────────────────────────────────────┐
│ 用户运行脚本                                               │
│ convert_pt_to_bin.bat model.pt calib_data                  │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────▼──────────────┐
        │ 步骤 1: 验证输入参数        │
        │ • 检查模型文件存在          │
        │ • 检查校准数据有效          │
        │ • 创建输出目录              │
        └──────────────┬──────────────┘
                       │
        ┌──────────────▼──────────────┐
        │ 步骤 2: ONNX 导出           │
        │ (在 Windows/Linux 上运行)   │
        │ • 加载 PyTorch 模型         │
        │ • 导出为 ONNX               │
        │ • 生成 config.yaml          │
        └──────────────┬──────────────┘
                       │
        ┌──────────────▼──────────────┐
        │ 步骤 3: Docker 环境检查     │
        │ • 检查 Docker 安装          │
        │ • 检查 Docker daemon        │
        │ • 下载/检查镜像             │
        └──────────────┬──────────────┘
                       │
        ┌──────────────▼──────────────┐
        │ 步骤 4: Docker 内编译       │
        │ (在 Docker 容器内运行)      │
        │ • hb_mapper checker         │
        │ • hb_mapper makertbin       │
        │ • hrt_model_exec            │
        └──────────────┬──────────────┘
                       │
        ┌──────────────▼──────────────┐
        │ 步骤 5: 验证结果            │
        │ • 检查 BIN 文件生成         │
        │ • 显示文件信息              │
        │ • 显示转换完成统计          │
        └──────────────┬──────────────┘
                       │
               ✅ 转换完成
                       │
        ┌──────────────▼──────────────┐
        │ 输出:                       │
        │ • model.onnx                │
        │ • config.yaml               │
        │ • model_detect_*.bin   ← 最终部署模型
        └─────────────────────────────┘
```

---

## ✅ 检查清单

### 开始前

- [ ] PyTorch 模型文件（`.pt`）
- [ ] 校准数据目录（至少 20 张 jpg/png 图像）
- [ ] Windows/Linux/macOS 系统
- [ ] Docker 已安装（如果未安装会自动检查并提示）
- [ ] 网络连接（用于下载 Docker 镜像）
- [ ] 磁盘空间（建议 10GB+）

### 执行中

脚本会自动检查以下内容：

- ✅ PyTorch 模型文件有效性
- ✅ 校准数据目录有效性
- ✅ Python/Docker 环境
- ✅ 网络连接和 Docker 镜像

### 完成后

验证以下文件是否生成：

- [ ] `*.onnx` 文件（ONNX 模型）
- [ ] `config.yaml` 文件（配置）
- [ ] `*_detect_*.bin` 文件（最终部署模型）

---

## 🐛 常见问题

### Q1: 脚本在哪个步骤失败了？

**A:** 脚本会清楚地显示进度：
```
╔════════════════════════════════════════╗
║  第 1 步: PyTorch -> ONNX 导出 (Windows) ║
╚════════════════════════════════════════╝
```

查看最后显示的步骤信息即可确定失败位置。

### Q2: "Docker daemon 未运行" 错误

**A:** 
- Windows: 启动 Docker Desktop
- Linux/macOS: 运行 `docker daemon` 或系统服务管理器启动 Docker

### Q3: "镜像下载失败"

**A:**
1. 检查网络连接
2. 手动尝试: `docker pull openexplorer/ai_toolchain_ubuntu_20_x5_cpu:v1.2.8`
3. 如果下载慢，可使用镜像加速服务

### Q4: ONNX 导出失败

**A:**
1. 检查 Python 环境: `python --version`
2. 检查依赖: `pip install ultralytics opencv-python`
3. 检查模型文件是否损坏

### Q5: Docker 编译超时

**A:**
1. 等待更长时间（某些模型需要 30+ 分钟）
2. 减少校准数据数量（但保持至少 20 张）
3. 检查磁盘空间是否足够

### Q6: BIN 文件没有生成

**A:**
1. 检查是否有编译错误（查看脚本输出）
2. 确保校准数据有效
3. 检查 Docker 内的日志文件

---

## 📂 输出文件结构

转换完成后的输出目录结构：

```
converted_models/
└── 20260715_number715/              ← 日期_模型名称文件夹
    ├── number715.pt                 (原始模型)
    ├── number715.onnx               (ONNX 模型)
    ├── config.yaml                  (编译配置)
    ├── compile.sh                   (Docker 编译脚本)
    ├── number715_detect_bayese_640x640_nv12.bin  (✅ 最终部署模型)
    ├── bpu_model_output/            (编译产物目录)
    │   ├── *.o
    │   ├── *.a
    │   └── ...
    └── .calibration_data_temporary_folder/  (校准数据缓存)
        └── ...
```

**关键文件**：
- `*.bin` - 🎯 最终部署模型（直接在 RDK X5 上使用）
- `*.onnx` - ONNX 格式中间模型
- `config.yaml` - 编译配置（可修改后重新编译）

---

## 🚀 下一步

### 成功转换后

1. ✅ 已生成 `.bin` 部署模型
2. ✅ 可直接在 RDK X5 设备上使用
3. ✅ 参考 `samples/vision/ultralytics_yolo/runtime/` 进行推理

### 如需调整参数

1. 修改工作目录中的 `config.yaml`
2. 调整优化参数（`optimize_level`, `jobs` 等）
3. 重新运行脚本即可

### 部署到 RDK X5

```python
# RDK X5 推理代码示例
from hbdk import libhbdk_hrt_model_runner

# 加载模型
model = libhbdk_hrt_model_runner.Model(
    "number715_detect_bayese_640x640_nv12.bin"
)

# 推理
output = model.forward(nv12_image_data)
```

---

## 💾 备份建议

转换完成后，建议备份以下内容：

```
backup/
├── number715.onnx           (ONNX 模型)
├── config.yaml              (编译配置)
└── number715_detect_*.bin   (部署模型)
```

这样如果需要重新编译或在其他环境中使用，可以直接使用备份的文件。

---

## 📞 获取帮助

如果遇到问题：

1. 查看脚本输出中的错误信息
2. 查看本项目根目录下的 `yolo_converter.py` 源码
3. 访问社区：https://forum.d-robotics.cc

---

## ✨ 总结

| 功能 | 说明 |
|------|------|
| **一键执行** | 无需手动干预，完全自动化 |
| **跨平台** | Windows/Linux/macOS 均支持 |
| **Docker 集成** | 自动下载并使用 Docker 镜像 |
| **错误检查** | 详细的错误提示和修复建议 |
| **时间预估** | 通常 10-40 分钟 |

---

**现在就开始一键转换吧！** 🚀

```batch
REM Windows
convert_pt_to_bin.bat model.pt calibration_data
```

```bash
# Linux
bash convert_pt_to_bin.sh model.pt calibration_data
```
