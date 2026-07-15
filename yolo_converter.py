#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
YOLOv8 模型一键转换脚本
自动完成从 PyTorch -> ONNX -> BPU BIN 的全流程
"""

import os
import sys
import argparse
import subprocess
import logging
from pathlib import Path
from typing import Optional

# 日志配置
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


class YOLOConverter:
    """YOLOv8 模型转换工具"""
    
    def __init__(self, 
                 pt_model: str,
                 cal_data_path: str,
                 output_dir: str = './models',
                 model_size: int = 640,
                 use_docker: bool = False):
        """
        初始化转换器
        
        Args:
            pt_model: PyTorch 模型路径 (.pt)
            cal_data_path: 校准数据集目录
            output_dir: 输出目录
            model_size: 模型输入大小 (640 或 1280)
            use_docker: 是否使用 Docker 环境
        """
        self.pt_model = Path(pt_model)
        self.cal_data_path = Path(cal_data_path)
        self.output_dir = Path(output_dir)
        self.model_size = model_size
        self.use_docker = use_docker
        self.script_dir = Path(__file__).parent
        
        # 创建输出目录
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # 验证输入
        self._validate_inputs()
    
    def _validate_inputs(self):
        """验证输入文件"""
        if not self.pt_model.exists():
            raise FileNotFoundError(f"PyTorch 模型不存在: {self.pt_model}")
        
        if not self.cal_data_path.exists():
            raise FileNotFoundError(f"校准数据目录不存在: {self.cal_data_path}")
        
        # 检查校准数据中是否有图像
        img_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.gif'}
        images = [f for f in self.cal_data_path.iterdir() 
                  if f.suffix.lower() in img_extensions]
        
        if not images:
            raise ValueError(f"校准数据目录中无图像文件: {self.cal_data_path}")
        
        logger.info(f"✓ 找到 {len(images)} 张校准图像")
    
    def step1_export_onnx(self) -> Path:
        """步骤 1：导出 ONNX 模型"""
        logger.info("\n" + "="*50)
        logger.info("步骤 1: 导出 ONNX 模型")
        logger.info("="*50)
        
        try:
            from ultralytics import YOLO
        except ImportError:
            logger.error("❌ 未找到 ultralytics，请先安装:")
            logger.error("  pip install ultralytics")
            sys.exit(1)
        
        logger.info(f"加载 PyTorch 模型: {self.pt_model}")
        model = YOLO(str(self.pt_model))
        
        # 导出为 ONNX
        onnx_path = self.output_dir / f"{self.pt_model.stem}.onnx"
        logger.info(f"导出为 ONNX: {onnx_path}")
        
        model.export(
            format='onnx',
            imgsz=self.model_size,
            opset=11,           # RDK X5 最大支持 opset 11
            simplify=True
        )
        
        if not onnx_path.exists():
            raise RuntimeError(f"ONNX 导出失败，文件不存在: {onnx_path}")
        
        logger.info(f"✓ ONNX 导出成功: {onnx_path}")
        return onnx_path
    
    def step2_prepare_config(self, onnx_path: Path) -> Path:
        """步骤 2：准备校准数据和 mapper 配置"""
        logger.info("\n" + "="*50)
        logger.info("步骤 2: 准备校准数据和配置")
        logger.info("="*50)
        
        # 检查 mapper.py 是否存在
        conversion_dir = self.script_dir.parent / 'samples' / 'vision' / 'ultralytics_yolo' / 'conversion'
        mapper_script = conversion_dir / 'mapper.py'
        
        if not mapper_script.exists():
            logger.warning(f"未找到 mapper.py: {mapper_script}")
            logger.warning("请确保在正确的项目目录中运行此脚本")
            return None
        
        # 运行 mapper.py
        cmd = [
            'python3',
            str(mapper_script),
            '--onnx', str(onnx_path),
            '--cal-images', str(self.cal_data_path),
            '--output-dir', str(self.output_dir)
        ]
        
        logger.info(f"执行命令: {' '.join(cmd)}")
        result = subprocess.run(cmd, cwd=str(self.output_dir), capture_output=False)
        
        if result.returncode != 0:
            raise RuntimeError("mapper.py 执行失败")
        
        config_path = self.output_dir / 'config.yaml'
        if not config_path.exists():
            raise RuntimeError(f"配置文件生成失败: {config_path}")
        
        logger.info(f"✓ 配置文件生成成功: {config_path}")
        return config_path
    
    def step3_check_config(self, config_path: Path) -> bool:
        """步骤 3：检查配置文件"""
        logger.info("\n" + "="*50)
        logger.info("步骤 3: 检查配置文件")
        logger.info("="*50)
        
        cmd = [
            'hb_mapper', 'checker',
            '--model-type', 'onnx',
            '--config', str(config_path)
        ]
        
        logger.info(f"执行命令: {' '.join(cmd)}")
        result = subprocess.run(cmd, cwd=str(self.output_dir))
        
        if result.returncode == 0:
            logger.info("✓ 配置文件检查通过")
            return True
        else:
            logger.error("❌ 配置文件检查失败")
            return False
    
    def step4_compile_model(self, config_path: Path) -> Optional[Path]:
        """步骤 4：编译 BIN 模型"""
        logger.info("\n" + "="*50)
        logger.info("步骤 4: 编译 BIN 模型（耗时较长，请耐心等待）")
        logger.info("="*50)
        
        cmd = [
            'hb_mapper', 'makertbin',
            '--config', str(config_path)
        ]
        
        logger.info(f"执行命令: {' '.join(cmd)}")
        logger.info("💡 提示：编译过程可能需要 5-30 分钟，请勿中断")
        
        result = subprocess.run(cmd, cwd=str(self.output_dir))
        
        if result.returncode != 0:
            logger.error("❌ 模型编译失败")
            return None
        
        # 查找生成的 .bin 文件
        bin_files = list(self.output_dir.glob('*.bin'))
        if not bin_files:
            logger.error("❌ 未找到 BIN 输出文件")
            return None
        
        bin_file = bin_files[0]
        logger.info(f"✓ BIN 模型编译成功: {bin_file}")
        logger.info(f"   文件大小: {bin_file.stat().st_size / 1024 / 1024:.2f} MB")
        return bin_file
    
    def step5_verify_model(self, bin_path: Path) -> bool:
        """步骤 5：验证编译结果"""
        logger.info("\n" + "="*50)
        logger.info("步骤 5: 验证编译结果")
        logger.info("="*50)
        
        # 查看模型信息
        cmd = [
            'hrt_model_exec', 'model_info',
            '--model_file', str(bin_path)
        ]
        
        logger.info(f"执行命令: {' '.join(cmd)}")
        result = subprocess.run(cmd, cwd=str(self.output_dir))
        
        if result.returncode != 0:
            logger.error("❌ 模型验证失败")
            return False
        
        logger.info("✓ 模型验证成功")
        
        # 性能评估
        logger.info("\n执行性能评估...")
        cmd = [
            'hrt_model_exec', 'perf',
            '--model_file', str(bin_path),
            '--thread_num', '1'
        ]
        
        subprocess.run(cmd, cwd=str(self.output_dir))
        return True
    
    def run(self) -> bool:
        """执行完整转换流程"""
        try:
            logger.info("\n🚀 开始 YOLOv8 模型转换流程")
            logger.info(f"   PyTorch 模型: {self.pt_model}")
            logger.info(f"   校准数据: {self.cal_data_path}")
            logger.info(f"   输出目录: {self.output_dir}")
            logger.info(f"   模型大小: {self.model_size}x{self.model_size}")
            
            # 步骤 1：导出 ONNX
            onnx_path = self.step1_export_onnx()
            
            # 步骤 2：准备配置
            config_path = self.step2_prepare_config(onnx_path)
            if not config_path:
                logger.warning("⚠️  跳过后续步骤（缺少 mapper.py）")
                logger.info("请在以下环境中继续转换过程:")
                logger.info("1. Docker: docker run -it -v /path:/data openexplorer/ai_toolchain_ubuntu_20_x5_cpu:v1.2.8")
                logger.info("2. 本地 Linux + hb_mapper 工具链")
                return True
            
            # 步骤 3：检查配置
            if not self.step3_check_config(config_path):
                logger.error("配置检查失败，请检查日志")
                return False
            
            # 步骤 4：编译模型
            bin_path = self.step4_compile_model(config_path)
            if not bin_path:
                logger.error("模型编译失败")
                return False
            
            # 步骤 5：验证结果
            self.step5_verify_model(bin_path)
            
            logger.info("\n" + "="*50)
            logger.info("✅ 转换流程完成！")
            logger.info("="*50)
            logger.info(f"部署模型位置: {bin_path}")
            logger.info(f"下一步：将此文件复制到 RDK X5 设备进行推理")
            return True
            
        except Exception as e:
            logger.error(f"\n❌ 转换失败: {e}")
            import traceback
            traceback.print_exc()
            return False


def main():
    parser = argparse.ArgumentParser(
        description='YOLOv8 模型一键转换脚本',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例用法:
  # 基本使用
  python3 yolo_converter.py --pt yolov8n.pt --cal-data ./calibration_images
  
  # 自定义输出目录和模型大小
  python3 yolo_converter.py --pt yolov8m.pt --cal-data ./calib --output ./converted_models --model-size 1280
  
  # 使用 Docker 环境
  python3 yolo_converter.py --pt yolov8n.pt --cal-data ./calib --docker
        """
    )
    
    parser.add_argument('--pt', type=str, required=True,
                        help='PyTorch 模型路径 (.pt 文件)')
    parser.add_argument('--cal-data', type=str, required=True,
                        help='校准数据集目录（包含 jpg/png 图像）')
    parser.add_argument('--output', type=str, default='./yolo_converted_models',
                        help='输出目录（默认: ./yolo_converted_models）')
    parser.add_argument('--model-size', type=int, default=640, choices=[640, 1280],
                        help='模型输入大小（默认: 640）')
    parser.add_argument('--docker', action='store_true',
                        help='使用 Docker 环境运行')
    
    args = parser.parse_args()
    
    # 创建转换器
    converter = YOLOConverter(
        pt_model=args.pt,
        cal_data_path=args.cal_data,
        output_dir=args.output,
        model_size=args.model_size,
        use_docker=args.docker
    )
    
    # 执行转换
    success = converter.run()
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
