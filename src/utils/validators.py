"""
Data validation utilities
"""
import numpy as np
from pathlib import Path

def validate_dataset_exists(dataset_path):
    """Check if dataset exists"""
    path = Path(dataset_path)
    if not path.exists():
        raise FileNotFoundError(f"Dataset not found: {dataset_path}")
    return True

def validate_model_inputs(data, expected_shape=None):
    """Validate model input data"""
    if not isinstance(data, (np.ndarray, list)):
        raise ValueError("Input must be numpy array or list")
    
    if expected_shape and isinstance(data, np.ndarray):
        if data.shape != expected_shape:
            raise ValueError(f"Expected shape {expected_shape}, got {data.shape}")
    
    return True

def validate_image_file(file_path):
    """Validate image file"""
    valid_extensions = ['.jpg', '.jpeg', '.png', '.bmp']
    path = Path(file_path)
    
    if not path.exists():
        raise FileNotFoundError(f"Image not found: {file_path}")
    
    if path.suffix.lower() not in valid_extensions:
        raise ValueError(f"Invalid image format. Expected {valid_extensions}")
    
    return True
