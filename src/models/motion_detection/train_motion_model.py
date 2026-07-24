#!/usr/bin/env python3
"""
SafeHer Motion Detection Model Training Script
Trains XGBoost model for motion-based threat detection with GPU support
"""

import os
import sys
import json
import numpy as np
import pandas as pd
import xgboost as xgb
from pathlib import Path
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, confusion_matrix, classification_report
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

class MotionModelTrainer:
    """Train motion detection models using XGBoost with GPU support"""
    
    def __init__(self, output_dir=".", use_gpu=True, device_id=0):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Configure GPU
        self.gpu_config = GPUTrainingConfig(use_gpu=use_gpu, device_id=device_id, batch_size=128)
        logger.info(f"⚙️  Training Configuration: {self.gpu_config}")
    
    def load_csv_dataset(self, csv_path, test_size=0.2, stratify_labels=True):
        """Load and prepare dataset from CSV file"""
        logger.info(f"📂 Loading dataset from {csv_path}")
        
        df = pd.read_csv(csv_path)
        logger.info(f"   Loaded {len(df)} samples with {len(df.columns) - 1} features")
        
        # Separate features and labels
        y = df['label'].values
        X = df.drop('label', axis=1).values
        
        # Display class distribution
        unique_labels, counts = np.unique(y, return_counts=True)
        logger.info(f"   Class distribution:")
        label_names = {0: 'Normal', 1: 'Fall', 2: 'Aggressive'}
        for label, count in zip(unique_labels, counts):
            label_name = label_names.get(label, f'Class {label}')
            percentage = (count / len(y)) * 100
            logger.info(f"      Label {label} ({label_name}): {count} samples ({percentage:.1f}%)")
        
        # Split data
        if stratify_labels:
            X_train, X_test, y_train, y_test = train_test_split(
                X, y, test_size=test_size, random_state=42, stratify=y
            )
        else:
            X_train, X_test, y_train, y_test = train_test_split(
                X, y, test_size=test_size, random_state=42
            )
        
        logger.info(f"   Train/Test split: {len(X_train)}/{len(X_test)}")
        logger.info(f"   Feature dimensions: {X_train.shape[1]} features")
        
        return X_train, X_test, y_train, y_test, df.columns[:-1].tolist()
        
    def generate_synthetic_training_data(self, n_samples=2000):
        """Generate synthetic training data for motion detection"""
        logger.info(f"🏗️ Generating {n_samples} synthetic motion sensor samples...")
        
        X = []
        y = []
        
        for i in range(n_samples):
            if np.random.rand() > 0.5:
                # Threat pattern (label=1) - sudden jerky movements
                accel_x = np.random.uniform(-8, 8)
                accel_y = np.random.uniform(-8, 8)
                accel_z = np.random.uniform(8, 12)
                gyro_x = np.random.uniform(-200, 200)
                gyro_y = np.random.uniform(-200, 200)
                gyro_z = np.random.uniform(-200, 200)
                label = 1
            else:
                # Normal movement (label=0)
                accel_x = np.random.uniform(-2, 2)
                accel_y = np.random.uniform(-2, 2)
                accel_z = np.random.uniform(8, 12)
                gyro_x = np.random.uniform(-50, 50)
                gyro_y = np.random.uniform(-50, 50)
                gyro_z = np.random.uniform(-50, 50)
                label = 0
            
            # Calculate magnitude
            magnitude = np.sqrt(accel_x**2 + accel_y**2 + accel_z**2)
            
            features = [accel_x, accel_y, accel_z, gyro_x, gyro_y, gyro_z, magnitude]
            X.append(features)
            y.append(label)
        
        return np.array(X), np.array(y)
    
    def train_xgboost_model(self, X_train, X_test, y_train, y_test, feature_names=None):
        """Train XGBoost model for motion detection with GPU acceleration"""
        logger.info("🤖 Training XGBoost motion detection model...")
        logger.info(f"📊 Training shape: {X_train.shape}, Test shape: {X_test.shape}")
        
        # Determine device
        device_id = self.gpu_config.get_device_id_for_framework()
        if device_id >= 0:
            logger.info(f"🚀 Using GPU acceleration (CUDA:{device_id})")
            tree_method = 'gpu_hist'
            gpu_id = device_id
        else:
            logger.info("💻 Using CPU for training")
            tree_method = 'hist'
            gpu_id = None
        
        # Create and train XGBoost model with GPU support
        xgb_params = {
            'n_estimators': 500,
            'max_depth': 6,
            'learning_rate': 0.1,
            'subsample': 0.8,
            'colsample_bytree': 0.8,
            'random_state': 42,
            'objective': 'binary:logistic',
            'eval_metric': 'logloss',
            'n_jobs': -1,
            'tree_method': tree_method,
            'device': 'cuda' if device_id >= 0 else 'cpu'
        }
        
        if device_id >= 0:
            xgb_params['gpu_id'] = gpu_id
        
        model = xgb.XGBClassifier(**xgb_params)
        
        # Train the model
        model.fit(X_train, y_train)
        
        # Clear GPU cache after training
        clear_gpu_cache()
        
        # Evaluate
        y_pred = model.predict(X_test)
        accuracy = accuracy_score(y_test, y_pred)
        precision = precision_score(y_test, y_pred)
        recall = recall_score(y_test, y_pred)
        f1 = f1_score(y_test, y_pred)
        
        logger.info(f"✅ Model Training Complete!")
        logger.info(f"   📊 Accuracy:  {accuracy:.4f} ({accuracy*100:.2f}%)")
        logger.info(f"   🎯 Precision: {precision:.4f}")
        logger.info(f"   📈 Recall:    {recall:.4f}")
        logger.info(f"   🔄 F1-Score:  {f1:.4f}")
        
        # Save model
        model_path = self.output_dir / "xgboost_motion_model.json"
        model.save_model(str(model_path))
        logger.info(f"💾 Model saved to {model_path}")
        
        # Generate classification report
        class_report = classification_report(y_test, y_pred, output_dict=True)
        
        # Save training results
        results = {
            'model_type': 'XGBoost',
            'accuracy': float(accuracy),
            'precision': float(precision),
            'recall': float(recall),
            'f1_score': float(f1),
            'n_estimators': 500,
            'max_depth': 6,
            'n_features': X_train.shape[1],
            'device': self.gpu_config.get_device_string(),
            'tree_method': tree_method,
            'feature_names': feature_names or [f'feature_{i}' for i in range(X_train.shape[1])],
            'classification_report': class_report,
            'training_samples': len(X_train),
            'test_samples': len(X_test)
        }
        
        results_path = self.output_dir / "motion_training_results.json"
        with open(results_path, 'w') as f:
            json.dump(results, f, indent=2)
        logger.info(f"📄 Results saved to {results_path}")
        
        return model, results
    
    def train(self, dataset_path=None):
        """Train motion detection model"""
        logger.info("🌟 Starting Motion Detection Model Training...")
        logger.info(f"📁 Output directory: {self.output_dir}")
        
        # Load dataset
        if dataset_path and Path(dataset_path).exists():
            logger.info(f"📂 Loading processed dataset from {dataset_path}")
            X_train, X_test, y_train, y_test, feature_names = self.load_csv_dataset(dataset_path)
        else:
            # Generate synthetic data as fallback
            logger.info("📊 Using synthetic training data")
            X, y = self.generate_synthetic_training_data()
            X_train, X_test, y_train, y_test = train_test_split(
                X, y, test_size=0.2, random_state=42, stratify=y
            )
            feature_names = [
                'acceleration_x', 'acceleration_y', 'acceleration_z',
                'gyroscope_x', 'gyroscope_y', 'gyroscope_z', 'magnitude'
            ]
        
        # Train model
        model, results = self.train_xgboost_model(X_train, X_test, y_train, y_test, feature_names)
        
        logger.info("🎉 Training complete!")
        return model, results

def main():
    """Main training function"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Train Motion Detection Model')
    parser.add_argument('--no-gpu', action='store_true', help='Disable GPU and use CPU')
    parser.add_argument('--device-id', type=int, default=0, help='GPU device ID (default: 0)')
    parser.add_argument('--dataset-path', type=str, default=None, help='Path to processed dataset CSV')
    args = parser.parse_args()
    
    # Initialize trainer with GPU support (output_dir is current directory)
    trainer = MotionModelTrainer(use_gpu=not args.no_gpu, device_id=args.device_id)
    
    # Determine dataset path
    if args.dataset_path:
        dataset_path = args.dataset_path
    else:
        # Check common locations
        possible_paths = [
            Path("../../dataset/processed/train_features.csv"),
            Path("../../../dataset/processed/train_features.csv"),
            Path("dataset/processed/train_features.csv"),
        ]
        dataset_path = None
        for path in possible_paths:
            if path.exists():
                dataset_path = str(path)
                break
    
    # Train model
    model, results = trainer.train(dataset_path)
    
    logger.info("\n" + "="*50)
    logger.info("MOTION MODEL TRAINING SUMMARY")
    logger.info("="*50)
    logger.info(f"Model Type: {results['model_type']}")
    logger.info(f"Device: {results.get('device', 'CPU')}")
    logger.info(f"Accuracy: {results['accuracy']:.4f}")
    logger.info(f"Precision: {results['precision']:.4f}")
    logger.info(f"Recall: {results['recall']:.4f}")
    logger.info(f"F1-Score: {results['f1_score']:.4f}")
    logger.info("="*50 + "\n")

if __name__ == "__main__":
    main()
