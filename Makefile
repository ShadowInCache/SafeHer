# Makefile for SafeHer Project

.PHONY: help setup install train test clean deploy

help:
	@echo "SafeHer Project Commands"
	@echo "========================"
	@echo "make setup      - Initial project setup"
	@echo "make install    - Install Python dependencies"
	@echo "make train      - Train all ML models"
	@echo "make test       - Test all APIs"
	@echo "make clean      - Clean build artifacts"
	@echo "make deploy     - Deploy to cloud"
	@echo ""

setup:
	@echo "Setting up SafeHer project..."
	python scripts/setup.py

install:
	@echo "Installing dependencies..."
	pip install -r requirements.txt

train:
	@echo "Training all models..."
	python scripts/train_all.py

test:
	@echo "Testing APIs..."
	python scripts/test_apis.py

clean:
	@echo "Cleaning build artifacts..."
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	rm -rf ml_training/outputs/* 2>/dev/null || true
	flutter clean

deploy:
	@echo "Deploying to cloud..."
	@echo "See docs/DEPLOYMENT.md for instructions"

flutter-setup:
	@echo "Setting up Flutter..."
	flutter pub get

flutter-run:
	@echo "Running Flutter app..."
	flutter run

flutter-build:
	@echo "Building Flutter APK..."
	flutter build apk --release
