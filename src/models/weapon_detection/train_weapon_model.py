#!/usr/bin/env python3
"""
SafeHer Weapon Detection Model Training Script
Trains YOLOv8 model for weapon/object detection with GPU support
"""

import os
import sys
import json
import numpy as np
from pathlib import Path
import logging

# Import GPU utilities from shared location
sys.path.insert(0, str(Path(__file__).parent.parent / "utils"))
from gpu_utils import GPUTrainingConfig, detect_gpu_availability, clear_gpu_cache

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class WeaponModelTrainer:
    """Train weapon detection models using YOLOv8 with GPU support"""
    
    def __init__(self, output_dir=".", use_gpu=True, device_id=0):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Configure GPU
        self.gpu_config = GPUTrainingConfig(use_gpu=use_gpu, device_id=device_id, batch_size=16)
        logger.info(f"⚙️  Training Configuration: {self.gpu_config}")
        
    def setup_yolov8_dataset(self, dataset_dir=None):
        """Setup YOLOv8 dataset structure"""
        logger.info("📂 Setting up YOLOv8 dataset structure...")
        
        # Create dataset structure
        dataset_path = Path(dataset_dir) if dataset_dir else Path("datasets/weapon_detection")
        
        # Create required directories
        (dataset_path / "images" / "train").mkdir(parents=True, exist_ok=True)
        (dataset_path / "images" / "val").mkdir(parents=True, exist_ok=True)
        (dataset_path / "labels" / "train").mkdir(parents=True, exist_ok=True)
        (dataset_path / "labels" / "val").mkdir(parents=True, exist_ok=True)
        
        logger.info(f"✅ Dataset structure created at {dataset_path}")
        
        return dataset_path
    
    def create_dataset_yaml(self, dataset_path):
        """Create dataset.yaml for YOLOv8 training"""
        yaml_content = {
            'path': str(dataset_path.absolute()),
            'train': 'images/train',
            'val': 'images/val',
            'nc': 2,
            'names': ['pistol', 'knife']
        }
        
        yaml_path = dataset_path / "data.yaml"
        
        # Write YAML format
        with open(yaml_path, 'w') as f:
            f.write(f"path: {yaml_content['path']}\n")
            f.write(f"train: {yaml_content['train']}\n")
            f.write(f"val: {yaml_content['val']}\n")
            f.write(f"nc: {yaml_content['nc']}\n")
            f.write(f"names: {yaml_content['names']}\n")
        
        logger.info(f"✅ Dataset YAML created at {yaml_path}")
        return yaml_path
    
    def train_yolov8_model(self, dataset_yaml):
        """Train YOLOv8 model for weapon detection with GPU acceleration"""
        try:
            from ultralytics import YOLO
            
            logger.info("🤖 Training YOLOv8 model for weapon detection...")
            
            # Get device configuration
            device = self.gpu_config.get_device_id_for_framework()
            if device >= 0:
                logger.info(f"🚀 Using GPU acceleration (CUDA:{device})")
            else:
                logger.info("💻 Using CPU for training")
                device = 'cpu'
            
            # Load YOLOv8 nano (lightweight)
            model = YOLO('yolov8n.pt')
            
            # Train the model with GPU support and data augmentation
            # Optimize batch size and workers for memory efficiency
            batch_size = max(8, self.gpu_config.batch_size // 2) if device != 'cpu' else 8
            
            results = model.train(
                data=str(dataset_yaml),
                epochs=100,
                imgsz=640,
                device=device,
                batch=batch_size,
                patience=20,
                save=True,
                project=str(self.output_dir),
                name='weapon_detection',
                verbose=True,
                amp=True,  # Mixed precision training for faster training on GPU
                workers=0,  # Disable data workers to reduce memory pressure on Windows
                cache=False,  # Disable image caching to reduce memory footprint
                # Data Augmentation to balance pistol/knife classes
                hsv_h=0.015,  # Image HSV-Hue augmentation
                hsv_s=0.7,    # Image HSV-Saturation augmentation
                hsv_v=0.4,    # Image HSV-Value augmentation
                degrees=10.0, # Image rotation (+/- deg)
                translate=0.1, # Image translation (+/- fraction)
                scale=0.5,    # Image scale (+/- gain)
                shear=0.0,    # Image shear (+/- deg)
                perspective=0.0, # Image perspective (+/- fraction)
                flipud=0.0,   # Image flip up-down (probability)
                fliplr=0.5,   # Image flip left-right (probability)
                mosaic=1.0,   # Image mosaic (probability)
                mixup=0.1,    # Image mixup (probability) - helps with imbalanced classes
                copy_paste=0.1  # Segment copy-paste (probability) - additional augmentation
            )
            
            # Clear GPU cache after training
            clear_gpu_cache()
            
            logger.info("✅ YOLOv8 training complete!")
            
            # Save training results
            results_dict = {
                'model_type': 'YOLOv8',
                'epochs': 100,
                'imgsz': 640,
                'batch_size': self.gpu_config.batch_size,
                'device': self.gpu_config.get_device_string(),
                'mixed_precision': True,
                'classes': ['pistol', 'knife'],
                'data_augmentation': {
                    'flipr': 0.5,
                    'mosaic': 1.0,
                    'mixup': 0.1,
                    'copy_paste': 0.1,
                    'hsv_augmentation': True
                },
                'status': 'trained'
            }
            
            results_path = self.output_dir / "weapon_training_results.json"
            with open(results_path, 'w') as f:
                json.dump(results_dict, f, indent=2)
            
            logger.info(f"📄 Results saved to {results_path}")
            
            return results
            
        except ImportError:
            logger.warning("⚠️ ultralytics not installed, cannot train YOLOv8")
            logger.info("📝 To train YOLOv8 model, install: pip install ultralytics")
            
            # Create placeholder results
            results_dict = {
                'model_type': 'YOLOv8',
                'epochs': 100,
                'imgsz': 640,
                'classes': ['pistol', 'knife'],
                'status': 'not_trained_ultralytics_missing'
            }
            
            results_path = self.output_dir / "weapon_training_results.json"
            with open(results_path, 'w') as f:
                json.dump(results_dict, f, indent=2)
            
            return None
    
    def create_classes_file(self):
        """Create weapons.names file with class labels"""
        classes = ['pistol', 'knife']

        classes_path = self.output_dir / "weapons.names"
        with open(classes_path, 'w') as f:
            for cls in classes:
                f.write(f"{cls}\n")

        logger.info(f"✅ Classes file created: {classes_path}")
        return classes_path
    
    def train(self, dataset_dir=None):
        """Train weapon detection model"""
        logger.info("🌟 Starting Weapon Detection Model Training...")
        logger.info(f"📁 Output directory: {self.output_dir}")
        
        # Create classes file
        self.create_classes_file()
        
        # Setup dataset
        dataset_path = self.setup_yolov8_dataset(dataset_dir)
        
        # Create dataset YAML
        dataset_yaml = self.create_dataset_yaml(dataset_path)
        
        # Train model
        results = self.train_yolov8_model(dataset_yaml)
        
        logger.info("🎉 Training setup complete!")
        return results

def main():
    """Main training function"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Train Weapon Detection Model')
    parser.add_argument('--no-gpu', action='store_true', help='Disable GPU and use CPU')
    parser.add_argument('--device-id', type=int, default=0, help='GPU device ID (default: 0)')
    args = parser.parse_args()
    
    # Initialize trainer with GPU support (output_dir is current directory)
    trainer = WeaponModelTrainer(use_gpu=not args.no_gpu, device_id=args.device_id)
    
    # Check for dataset directory (relative to this script's location)
    # Path: train_weapon_model.py -> weapon_detection -> models -> src -> SafeHer
    script_dir = Path(__file__).parent
    dataset_dir = script_dir.parent.parent.parent / "datasets" / "weapon_detection"
    
    # Train model
    results = trainer.train(dataset_dir if dataset_dir.exists() else None)
    
    logger.info("\n" + "="*50)
    logger.info("WEAPON MODEL TRAINING SUMMARY")
    logger.info("="*50)
    logger.info("Model Type: YOLOv8n (nano)")
    logger.info(f"Device: {trainer.gpu_config.get_device_string()}")
    logger.info("Classes: pistol, knife")
    logger.info("Data Augmentation: Enabled (mixup, mosaic, copy_paste)")
    logger.info("Status: Ready for training with ultralytics")
    logger.info("="*50 + "\n")

if __name__ == "__main__":
    main()
