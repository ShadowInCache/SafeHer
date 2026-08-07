#!/usr/bin/env python3
"""
SafeHer Voice Detection Model Training Script
Trains machine learning models for vocal distress detection with GPU support
"""

import os
import sys
import json
import pickle
import numpy as np
import librosa
import soundfile as sf
from pathlib import Path
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, confusion_matrix
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

class VoiceModelTrainer:
    """Train voice detection models with optional GPU acceleration"""
    
    def __init__(self, output_dir=".", use_gpu=True, device_id=0):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.sample_rate = 16000
        self.duration = 2  # seconds
        
        # Configure GPU (for future cuML support)
        self.gpu_config = GPUTrainingConfig(use_gpu=use_gpu, device_id=device_id)
        self.use_cuml = False
        
        # Try to use GPU-accelerated Random Forest if available
        if use_gpu:
            try:
                from cuml.ensemble import RandomForestClassifier as cuMLRandomForest
                self.cuml_rf = cuMLRandomForest
                self.use_cuml = True
                logger.info(f"✅ RAPIDS cuML available - Using GPU-accelerated Random Forest")
            except ImportError:
                logger.info(f"ℹ️  RAPIDS cuML not available - Using CPU RandomForest")
                logger.info(f"   💡 For GPU acceleration, install: pip install cuml")
        
        logger.info(f"⚙️  Training Configuration: {self.gpu_config}")
        
    def extract_audio_features(self, audio_path):
        """Extract features from audio file"""
        try:
            # Load audio
            y, sr = librosa.load(audio_path, sr=self.sample_rate, duration=self.duration)
            
            # Extract features
            features = {}
            
            # RMS Energy
            features['rms_energy'] = float(np.mean(librosa.feature.rms(y=y)))
            
            # Zero Crossing Rate
            features['zcr'] = float(np.mean(librosa.feature.zero_crossing_rate(y)))
            
            # Spectral Centroid
            features['spectral_centroid'] = float(np.mean(librosa.feature.spectral_centroid(y=y, sr=sr)))
            
            # Spectral Rolloff
            features['spectral_rolloff'] = float(np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr)))
            
            # MFCC (Mel-Frequency Cepstral Coefficients)
            mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)
            features['mfcc_mean'] = float(np.mean(mfcc))
            features['mfcc_std'] = float(np.std(mfcc))
            
            # Chroma Features
            chroma = librosa.feature.chroma_stft(y=y, sr=sr)
            features['chroma_mean'] = float(np.mean(chroma))
            features['chroma_std'] = float(np.std(chroma))
            
            # Spectral Contrast
            contrast = librosa.feature.spectral_contrast(y=y, sr=sr)
            features['contrast_mean'] = float(np.mean(contrast))
            features['contrast_std'] = float(np.std(contrast))
            
            # Tempogram (Onset Strength)
            features['onset_strength'] = float(np.mean(librosa.onset.onset_strength(y=y, sr=sr)))
            
            # Pitch-based features
            S = librosa.magphase(librosa.stft(y))[0]
            features['spectral_flux'] = float(np.mean(np.sqrt(np.sum(np.diff(S, axis=1)**2, axis=0))))
            
            return features
            
        except Exception as e:
            logger.error(f"Error extracting features from {audio_path}: {e}")
            return None
    
    def generate_synthetic_training_data(self, n_samples=500):
        """Generate synthetic training data for voice detection"""
        logger.info(f"🏗️ Generating {n_samples} synthetic audio samples...")
        
        X = []
        y = []
        
        for i in range(n_samples):
            features = {}
            
            if np.random.rand() > 0.5:
                # Distress signal (label=1)
                features['rms_energy'] = np.random.uniform(0.3, 0.8)  # Higher energy
                features['zcr'] = np.random.uniform(0.15, 0.35)  # Higher zero crossing
                features['spectral_centroid'] = np.random.uniform(2500, 4000)  # Higher frequency
                features['spectral_rolloff'] = np.random.uniform(6000, 8000)
                features['mfcc_mean'] = np.random.uniform(-50, -30)
                features['mfcc_std'] = np.random.uniform(10, 20)
                features['chroma_mean'] = np.random.uniform(0.4, 0.7)
                features['chroma_std'] = np.random.uniform(0.15, 0.35)
                features['contrast_mean'] = np.random.uniform(4, 6)
                features['contrast_std'] = np.random.uniform(1, 2)
                features['onset_strength'] = np.random.uniform(0.05, 0.15)
                features['spectral_flux'] = np.random.uniform(0.3, 0.6)
                label = 1
            else:
                # Normal speech (label=0)
                features['rms_energy'] = np.random.uniform(0.1, 0.3)
                features['zcr'] = np.random.uniform(0.05, 0.15)
                features['spectral_centroid'] = np.random.uniform(1500, 2500)
                features['spectral_rolloff'] = np.random.uniform(4000, 6000)
                features['mfcc_mean'] = np.random.uniform(-80, -50)
                features['mfcc_std'] = np.random.uniform(5, 15)
                features['chroma_mean'] = np.random.uniform(0.2, 0.5)
                features['chroma_std'] = np.random.uniform(0.05, 0.2)
                features['contrast_mean'] = np.random.uniform(2, 4)
                features['contrast_std'] = np.random.uniform(0.5, 1.5)
                features['onset_strength'] = np.random.uniform(0.01, 0.05)
                features['spectral_flux'] = np.random.uniform(0.1, 0.3)
                label = 0
            
            feature_values = list(features.values())
            X.append(feature_values)
            y.append(label)
        
        return np.array(X), np.array(y)
    
    def train_random_forest_model(self, X, y):
        """Train Random Forest model for voice detection"""
        logger.info("🤖 Training voice detection model...")
        
        # Split data
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42, stratify=y
        )
        
        # Scale features
        scaler = StandardScaler()
        X_train_scaled = scaler.fit_transform(X_train)
        X_test_scaled = scaler.transform(X_test)
        
        # Choose model based on GPU availability
        if self.use_cuml:
            logger.info(f"🚀 Using GPU-accelerated RAPIDS cuML Random Forest")
            model = self.cuml_rf(
                n_estimators=200,
                max_depth=15,
                output_type='numpy'
            )
        else:
            logger.info(f"💻 Using CPU scikit-learn Random Forest")
            model = RandomForestClassifier(
                n_estimators=200,
                max_depth=15,
                min_samples_split=5,
                min_samples_leaf=2,
                random_state=42,
                n_jobs=-1
            )
        
        # Train the model
        model.fit(X_train_scaled, y_train)
        
        # Clear GPU cache if used
        clear_gpu_cache()
        
        # Evaluate
        y_pred = model.predict(X_test_scaled)
        accuracy = accuracy_score(y_test, y_pred)
        precision = precision_score(y_test, y_pred)
        recall = recall_score(y_test, y_pred)
        f1 = f1_score(y_test, y_pred)
        
        logger.info(f"✅ Model Training Complete!")
        logger.info(f"   📊 Accuracy:  {accuracy:.4f} ({accuracy*100:.2f}%)")
        logger.info(f"   🎯 Precision: {precision:.4f}")
        logger.info(f"   📈 Recall:    {recall:.4f}")
        logger.info(f"   🔄 F1-Score:  {f1:.4f}")
        
        # Save scaler
        scaler_path = self.output_dir / "voice_scaler.pkl"
        with open(scaler_path, 'wb') as f:
            pickle.dump(scaler, f)
        logger.info(f"💾 Scaler saved to {scaler_path}")
        
        # Save model
        model_path = self.output_dir / "voice_model.pkl"
        with open(model_path, 'wb') as f:
            pickle.dump(model, f)
        logger.info(f"💾 Model saved to {model_path}")
        
        # Save training results
        results = {
            'model_type': 'RandomForest (cuML)' if self.use_cuml else 'RandomForest',
            'accuracy': accuracy,
            'precision': precision,
            'recall': recall,
            'f1_score': f1,
            'n_estimators': 200,
            'max_depth': 15,
            'n_features': X.shape[1],
            'device': self.gpu_config.get_device_string(),
            'gpu_accelerated': self.use_cuml,
            'feature_names': [
                'rms_energy', 'zcr', 'spectral_centroid', 'spectral_rolloff',
                'mfcc_mean', 'mfcc_std', 'chroma_mean', 'chroma_std',
                'contrast_mean', 'contrast_std', 'onset_strength', 'spectral_flux'
            ]
        }
        
        results_path = self.output_dir / "voice_training_results.json"
        with open(results_path, 'w') as f:
            json.dump(results, f, indent=2)
        logger.info(f"📄 Results saved to {results_path}")
        
        return model, scaler, results
    
    def train(self, dataset_dir=None):
        """Train voice detection model"""
        logger.info("🌟 Starting Voice Detection Model Training...")
        logger.info(f"📁 Output directory: {self.output_dir}")
        
        # Check if real dataset exists
        if dataset_dir and Path(dataset_dir).exists():
            logger.info(f"📂 Loading audio files from {dataset_dir}")
            # Load and process real audio files
            X = []
            y = []
            
            for label_dir in Path(dataset_dir).iterdir():
                if not label_dir.is_dir():
                    continue
                
                label = 1 if 'distress' in label_dir.name.lower() else 0
                audio_files = list(label_dir.glob('*.wav')) + list(label_dir.glob('*.mp3'))
                
                logger.info(f"Processing {label_dir.name}: {len(audio_files)} files")
                
                for audio_file in audio_files:
                    features = self.extract_audio_features(str(audio_file))
                    if features:
                        X.append(list(features.values()))
                        y.append(label)
            
            if X:
                X = np.array(X)
                y = np.array(y)
                logger.info(f"✅ Loaded {len(X)} samples from real dataset")
            else:
                logger.warning("⚠️ No audio files found, generating synthetic data")
                X, y = self.generate_synthetic_training_data()
        else:
            # Generate synthetic data if no dataset
            logger.info("📊 Using synthetic training data")
            X, y = self.generate_synthetic_training_data()
        
        # Train model
        model, scaler, results = self.train_random_forest_model(X, y)
        
        logger.info("🎉 Training complete!")
        return model, scaler, results

def main():
    """Main training function"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Train Voice Detection Model')
    parser.add_argument('--no-gpu', action='store_true', help='Disable GPU and use CPU')
    parser.add_argument('--device-id', type=int, default=0, help='GPU device ID (default: 0)')
    args = parser.parse_args()
    
    # Initialize trainer with GPU support (output_dir is current directory)
    trainer = VoiceModelTrainer(use_gpu=not args.no_gpu, device_id=args.device_id)
    
    # Check for dataset directory
    dataset_dir = Path("datasets/voice_detection")
    
    # Train model
    model, scaler, results = trainer.train(dataset_dir if dataset_dir.exists() else None)
    
    logger.info("\n" + "="*50)
    logger.info("VOICE MODEL TRAINING SUMMARY")
    logger.info("="*50)
    logger.info(f"Model Type: {results['model_type']}")
    logger.info(f"Device: {results.get('device', 'CPU')}")
    logger.info(f"GPU Accelerated: {'Yes (RAPIDS cuML)' if results.get('gpu_accelerated') else 'No'}")
    logger.info(f"Accuracy: {results['accuracy']:.4f}")
    logger.info(f"Precision: {results['precision']:.4f}")
    logger.info(f"Recall: {results['recall']:.4f}")
    logger.info(f"F1-Score: {results['f1_score']:.4f}")
    logger.info("="*50 + "\n")

if __name__ == "__main__":
    main()
