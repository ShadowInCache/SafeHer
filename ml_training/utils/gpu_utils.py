#!/usr/bin/env python3
"""
SafeHer GPU Utilities Module
Detects and manages GPU resources for model training
"""

import logging
import numpy as np
from pathlib import Path

logger = logging.getLogger(__name__)

def detect_gpu_availability():
    """Detect available GPU devices"""
    gpu_info = {
        'cuda_available': False,
        'cudnn_available': False,
        'device_count': 0,
        'device_names': [],
        'total_memory': 0
    }
    
    # Check CUDA availability
    try:
        import torch
        gpu_info['cuda_available'] = torch.cuda.is_available()
        gpu_info['device_count'] = torch.cuda.device_count()
        gpu_info['cudnn_available'] = torch.backends.cudnn.enabled
        
        if gpu_info['cuda_available']:
            for i in range(gpu_info['device_count']):
                device_props = torch.cuda.get_device_properties(i)
                gpu_info['device_names'].append(device_props.name)
                gpu_info['total_memory'] += device_props.total_memory / (1024**3)  # Convert to GB
            
            logger.info(f"✅ CUDA Available - Found {gpu_info['device_count']} GPU(s)")
            for i, name in enumerate(gpu_info['device_names']):
                logger.info(f"   GPU {i}: {name}")
        else:
            logger.warning("⚠️ CUDA not available - Will use CPU")
    
    except ImportError:
        logger.warning("⚠️ PyTorch not installed - Cannot detect GPU")
    except Exception as e:
        logger.warning(f"⚠️ Error detecting GPU: {e}")
    
    return gpu_info

def get_gpu_memory_usage():
    """Get GPU memory usage"""
    try:
        import torch
        if torch.cuda.is_available():
            memory_info = []
            for i in range(torch.cuda.device_count()):
                torch.cuda.set_device(i)
                allocated = torch.cuda.memory_allocated(i) / (1024**3)  # GB
                reserved = torch.cuda.memory_reserved(i) / (1024**3)    # GB
                total = torch.cuda.get_device_properties(i).total_memory / (1024**3)  # GB
                
                memory_info.append({
                    'device_id': i,
                    'device_name': torch.cuda.get_device_name(i),
                    'allocated_gb': allocated,
                    'reserved_gb': reserved,
                    'total_gb': total,
                    'available_gb': total - allocated
                })
            return memory_info
    except:
        pass
    
    return []

def print_gpu_status():
    """Print GPU status information"""
    print("\n" + "="*70)
    print("🖥️  GPU AVAILABILITY CHECK")
    print("="*70 + "\n")
    
    gpu_info = detect_gpu_availability()
    
    if gpu_info['cuda_available']:
        print(f"✅ CUDA Available: YES")
        print(f"📊 GPU Device Count: {gpu_info['device_count']}")
        print(f"💾 Total GPU Memory: {gpu_info['total_memory']:.2f} GB")
        print(f"🎯 cuDNN Available: {'YES' if gpu_info['cudnn_available'] else 'NO'}")
        
        print(f"\n📋 GPU Devices:")
        for i, name in enumerate(gpu_info['device_names']):
            print(f"   GPU {i}: {name}")
        
        # Show memory usage
        memory_info = get_gpu_memory_usage()
        if memory_info:
            print(f"\n💾 GPU Memory Usage:")
            for mem in memory_info:
                print(f"   GPU {mem['device_id']}: {mem['allocated_gb']:.2f}GB / {mem['total_gb']:.2f}GB")
    else:
        print("❌ CUDA Available: NO")
        print("⚠️  Training will use CPU - GPU will provide significant speedup")
        print("\n💡 To enable GPU training:")
        print("   1. Install NVIDIA CUDA Toolkit")
        print("   2. Install cuDNN")
        print("   3. Install GPU-enabled PyTorch: pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118")
    
    print("\n" + "="*70 + "\n")
    return gpu_info

def optimize_batch_size_for_gpu(default_batch_size=32):
    """Optimize batch size based on available GPU memory"""
    try:
        import torch
        if not torch.cuda.is_available():
            return default_batch_size
        
        # Get available GPU memory in GB
        total_memory = torch.cuda.get_device_properties(0).total_memory / (1024**3)
        
        # Estimate batch size: reserve 1GB for model, use rest for data
        available_for_data = max(total_memory - 1, 2)
        
        # Rough estimate: ~0.1GB per 32 samples for typical models
        optimal_batch_size = int((available_for_data / 0.1) * 32)
        
        # Round to nearest power of 2
        optimal_batch_size = 2 ** int(np.log2(optimal_batch_size))
        
        logger.info(f"🎯 Optimized batch size: {optimal_batch_size} (GPU memory: {total_memory:.1f}GB)")
        return optimal_batch_size
    
    except Exception as e:
        logger.warning(f"⚠️ Could not optimize batch size: {e}")
        return default_batch_size

def clear_gpu_cache():
    """Clear GPU cache to free memory"""
    try:
        import torch
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
            logger.info("🧹 GPU cache cleared")
    except:
        pass

class GPUTrainingConfig:
    """Configuration for GPU-accelerated training"""
    
    def __init__(self, use_gpu=True, device_id=0, batch_size=32, mixed_precision=False):
        self.use_gpu = use_gpu
        self.device_id = device_id
        self.batch_size = batch_size
        self.mixed_precision = mixed_precision
        
        # Detect GPU availability if use_gpu is True
        if use_gpu:
            gpu_info = detect_gpu_availability()
            if not gpu_info['cuda_available']:
                logger.warning("⚠️ GPU requested but not available - falling back to CPU")
                self.use_gpu = False
            elif device_id >= gpu_info['device_count']:
                logger.warning(f"⚠️ Device {device_id} not available - using device 0")
                self.device_id = 0
    
    def get_device_string(self):
        """Get device string for framework (e.g., 'cuda:0' or 'cpu')"""
        if self.use_gpu:
            return f"cuda:{self.device_id}"
        return "cpu"
    
    def get_device_id_for_framework(self):
        """Get device ID for XGBoost/YOLOv8 etc."""
        return self.device_id if self.use_gpu else -1
    
    def __str__(self):
        device_str = f"GPU (CUDA:{self.device_id})" if self.use_gpu else "CPU"
        return f"Device: {device_str}, Batch Size: {self.batch_size}, Mixed Precision: {self.mixed_precision}"

if __name__ == "__main__":
    print_gpu_status()
