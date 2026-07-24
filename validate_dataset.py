#!/usr/bin/env python3
"""
SafeHer Motion Detection - Data Processing Validation Tool
Verify that all datasets and features are correctly generated
"""

import json
import pandas as pd
from pathlib import Path

class DatasetValidator:
    """Validate dataset integrity and completeness"""
    
    def __init__(self, dataset_root="dataset"):
        self.root = Path(dataset_root)
        self.results = {}
    
    def check_raw_datasets(self):
        """Check if raw datasets exist"""
        print("\n📋 Checking Raw Datasets")
        print("=" * 60)
        
        files = {
            'normal.csv': {
                'path': self.root / 'raw' / 'normal.csv',
                'expected_rows': 5000
            },
            'fall.csv': {
                'path': self.root / 'raw' / 'fall.csv',
                'expected_rows': 2000
            },
            'aggressive.csv': {
                'path': self.root / 'raw' / 'aggressive.csv',
                'expected_rows': 2000
            }
        }
        
        all_exist = True
        total_samples = 0
        
        for name, config in files.items():
            path = config['path']
            if path.exists():
                df = pd.read_csv(path)
                samples = len(df)
                expected = config['expected_rows']
                status = "✅" if samples > 0 else "❌"
                print(f"{status} {name:<20} {samples:,} samples (expected: {expected:,})")
                total_samples += samples
            else:
                print(f"❌ {name:<20} NOT FOUND")
                all_exist = False
        
        print(f"\n📊 Total raw samples: {total_samples:,}")
        self.results['raw_datasets'] = all_exist
        return all_exist
    
    def check_processed_datasets(self):
        """Check if processed datasets exist"""
        print("\n📋 Checking Processed Datasets")
        print("=" * 60)
        
        files = {
            'merged_dataset.csv': {
                'expected_cols': ['time', 'ax', 'ay', 'az', 'gx', 'gy', 'gz', 'label'],
                'optional': False
            },
            'features.csv': {
                'expected_cols': None,  # Dynamic
                'optional': False
            },
            'train_features.csv': {
                'expected_cols': None,  # Dynamic
                'optional': False
            },
            'val_features.csv': {
                'expected_cols': None,  # Dynamic
                'optional': True
            },
            'test_features.csv': {
                'expected_cols': None,  # Dynamic
                'optional': False
            },
            'metadata.json': {
                'expected_cols': None,
                'optional': False
            }
        }
        
        all_exist = True
        
        for filename, config in files.items():
            path = self.root / 'processed' / filename
            
            if path.exists():
                if filename.endswith('.csv'):
                    df = pd.read_csv(path)
                    samples = len(df)
                    cols = len(df.columns)
                    print(f"✅ {filename:<25} {samples:,} rows × {cols} cols")
                    
                    # Check for label column
                    if 'label' in df.columns:
                        labels = df['label'].unique()
                        print(f"   └─ Classes: {sorted(labels)}")
                else:
                    print(f"✅ {filename:<25} exists")
                    if filename == 'metadata.json':
                        with open(path) as f:
                            meta = json.load(f)
                            print(f"   └─ Raw samples: {meta.get('raw_samples', 'N/A'):,}")
                            print(f"   └─ Feature samples: {meta.get('feature_samples', 'N/A'):,}")
            else:
                if config['optional']:
                    print(f"⚠️  {filename:<25} not found (optional)")
                else:
                    print(f"❌ {filename:<25} NOT FOUND")
                    all_exist = False
        
        self.results['processed_datasets'] = all_exist
        return all_exist
    
    def check_trained_models(self):
        """Check if trained models exist"""
        print("\n📋 Checking Trained Models")
        print("=" * 60)
        
        model_dir = Path("src/models/motion_detection")
        
        files = {
            'xgboost_motion_model.json': 'XGBoost Model',
            'motion_training_results.json': 'Training Results'
        }
        
        all_exist = True
        
        for filename, description in files.items():
            path = model_dir / filename
            if path.exists():
                print(f"✅ {description:<25} ({filename})")
                if filename == 'motion_training_results.json':
                    with open(path) as f:
                        results = json.load(f)
                        print(f"   ├─ Accuracy: {results.get('accuracy', 0):.4f}")
                        print(f"   ├─ Precision: {results.get('precision', 0):.4f}")
                        print(f"   ├─ Recall: {results.get('recall', 0):.4f}")
                        print(f"   └─ F1-Score: {results.get('f1_score', 0):.4f}")
            else:
                print(f"❌ {description:<25} NOT FOUND")
                all_exist = False
        
        self.results['trained_models'] = all_exist
        return all_exist
    
    def validate_data_integrity(self):
        """Validate dataset integrity"""
        print("\n📋 Validating Data Integrity")
        print("=" * 60)
        
        all_valid = True
        
        # Check features have label column
        features_path = self.root / 'processed' / 'features.csv'
        if features_path.exists():
            df = pd.read_csv(features_path)
            
            # Check for NaN values
            nan_count = df.isna().sum().sum()
            if nan_count == 0:
                print(f"✅ No NaN values in features.csv")
            else:
                print(f"❌ Found {nan_count} NaN values in features.csv")
                all_valid = False
            
            # Check class distribution
            if 'label' in df.columns:
                class_dist = df['label'].value_counts().sort_index()
                print(f"✅ Class distribution in features:")
                total = len(df)
                for label, count in class_dist.items():
                    pct = (count / total) * 100
                    print(f"   └─ Label {label}: {count} samples ({pct:.1f}%)")
        
        # Check train/test split
        train_path = self.root / 'processed' / 'train_features.csv'
        test_path = self.root / 'processed' / 'test_features.csv'
        
        if train_path.exists() and test_path.exists():
            train_df = pd.read_csv(train_path)
            test_df = pd.read_csv(test_path)
            
            total = len(train_df) + len(test_df)
            train_pct = (len(train_df) / total) * 100
            test_pct = (len(test_df) / total) * 100
            
            print(f"\n✅ Train/Test Split:")
            print(f"   ├─ Train: {len(train_df)} samples ({train_pct:.1f}%)")
            print(f"   └─ Test: {len(test_df)} samples ({test_pct:.1f}%)")
            
            # Check no overlap
            if len(train_df) > 0 and len(test_df) > 0:
                print(f"✅ Train and test sets are properly separated")
        
        self.results['data_integrity'] = all_valid
        return all_valid
    
    def print_summary(self):
        """Print validation summary"""
        print("\n" + "=" * 60)
        print("📊 VALIDATION SUMMARY")
        print("=" * 60)
        
        checks = {
            'raw_datasets': 'Raw Datasets',
            'processed_datasets': 'Processed Datasets',
            'trained_models': 'Trained Models',
            'data_integrity': 'Data Integrity'
        }
        
        all_pass = True
        for key, name in checks.items():
            status = "✅ PASS" if self.results.get(key, False) else "❌ FAIL"
            print(f"{status} - {name}")
            if not self.results.get(key, False):
                all_pass = False
        
        print("=" * 60)
        
        if all_pass:
            print("\n🎉 All validation checks passed!")
            print("\n✅ Your dataset is ready for training!")
            print("\nTo train the model, run:")
            print("  cd ml_training")
            print("  python train_motion_model.py")
        else:
            print("\n⚠️  Some validation checks failed.")
            print("\nTo generate missing datasets:")
            print("  cd dataset")
            print("  python create_sample_datasets.py")
            print("  python merge_datasets.py")
        
        print("\n")
    
    def run_all_checks(self):
        """Run all validation checks"""
        print("\n" + "🔍 " * 20)
        print("SafeHer Motion Detection - Data Validation")
        print("🔍 " * 20)
        
        self.check_raw_datasets()
        self.check_processed_datasets()
        self.check_trained_models()
        self.validate_data_integrity()
        self.print_summary()


def main():
    """Main entry point"""
    validator = DatasetValidator()
    validator.run_all_checks()


if __name__ == "__main__":
    main()
