#!/bin/bash
# SafeHer Cloud Functions Deployment Script
# Supports AWS Lambda, Google Cloud Functions, and Azure Functions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FUNCTIONS=("motion_detection" "voice_analysis" "weapon_detection" "threat_fusion")
REGION=${AWS_REGION:-us-east-1}
RUNTIME="python3.11"
TIMEOUT=60
MEMORY=512

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║                    🚀 SafeHer Cloud Functions Deployment 🚀              ║"
    echo "║                                                                          ║"
    echo "║  Deploy AI/ML serverless functions for threat detection                 ║"
    echo "║                                                                          ║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

usage() {
    echo "Usage: $0 [aws|gcp|azure] [function_name]"
    echo ""
    echo "Cloud Providers:"
    echo "  aws   - Deploy to AWS Lambda"
    echo "  gcp   - Deploy to Google Cloud Functions"
    echo "  azure - Deploy to Azure Functions"
    echo ""
    echo "Functions:"
    echo "  motion_detection - Motion sensor threat detection"
    echo "  voice_analysis   - Voice/audio distress detection"
    echo "  weapon_detection - Weapon/object detection"
    echo "  threat_fusion    - Multi-source threat correlation"
    echo "  all             - Deploy all functions"
    echo ""
    echo "Examples:"
    echo "  $0 aws all                    # Deploy all to AWS"
    echo "  $0 gcp motion_detection       # Deploy motion detection to GCP"
    echo "  $0 azure threat_fusion        # Deploy threat fusion to Azure"
}

check_dependencies() {
    echo -e "${YELLOW}🔍 Checking dependencies...${NC}"
    
    case $1 in
        aws)
            if ! command -v aws &> /dev/null; then
                echo -e "${RED}❌ AWS CLI not found. Install: pip install awscli${NC}"
                exit 1
            fi
            if ! command -v zip &> /dev/null; then
                echo -e "${RED}❌ zip not found. Please install zip utility${NC}"
                exit 1
            fi
            ;;
        gcp)
            if ! command -v gcloud &> /dev/null; then
                echo -e "${RED}❌ Google Cloud SDK not found${NC}"
                exit 1
            fi
            ;;
        azure)
            if ! command -v az &> /dev/null; then
                echo -e "${RED}❌ Azure CLI not found${NC}"
                exit 1
            fi
            ;;
    esac
    
    echo -e "${GREEN}✅ Dependencies OK${NC}"
}

test_functions() {
    echo -e "${YELLOW}🧪 Running function tests...${NC}"
    
    if python3 test_functions.py; then
        echo -e "${GREEN}✅ All tests passed${NC}"
    else
        echo -e "${RED}❌ Tests failed. Fix issues before deployment.${NC}"
        exit 1
    fi
}

deploy_aws_lambda() {
    local func_name=$1
    echo -e "${BLUE}🚀 Deploying $func_name to AWS Lambda...${NC}"
    
    # Create deployment package
    cd "$func_name"
    
    # Install dependencies
    if [ -f requirements.txt ]; then
        pip install -r requirements.txt -t .
    fi
    
    # Create zip package
    zip -r "../${func_name}.zip" . -x "*.pyc" "__pycache__/*"
    cd ..
    
    # Deploy to Lambda
    aws lambda create-function \
        --function-name "safeher-${func_name}" \
        --runtime "$RUNTIME" \
        --role "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/lambda-execution-role" \
        --handler "main.lambda_handler" \
        --zip-file "fileb://${func_name}.zip" \
        --timeout $TIMEOUT \
        --memory-size $MEMORY \
        --region $REGION \
        2>/dev/null || \
    aws lambda update-function-code \
        --function-name "safeher-${func_name}" \
        --zip-file "fileb://${func_name}.zip" \
        --region $REGION
    
    # Clean up
    rm "${func_name}.zip"
    
    echo -e "${GREEN}✅ $func_name deployed to AWS Lambda${NC}"
}

deploy_gcp_function() {
    local func_name=$1
    echo -e "${BLUE}🚀 Deploying $func_name to Google Cloud Functions...${NC}"
    
    cd "$func_name"
    
    gcloud functions deploy "safeher-${func_name}" \
        --runtime "$RUNTIME" \
        --trigger-http \
        --allow-unauthenticated \
        --entry-point gcp_handler \
        --timeout $TIMEOUT \
        --memory "${MEMORY}MB"
    
    cd ..
    
    echo -e "${GREEN}✅ $func_name deployed to Google Cloud Functions${NC}"
}

deploy_azure_function() {
    local func_name=$1
    echo -e "${BLUE}🚀 Deploying $func_name to Azure Functions...${NC}"
    
    # Azure Functions deployment would require more setup
    # This is a placeholder for Azure deployment logic
    echo -e "${YELLOW}ℹ️ Azure deployment requires additional setup${NC}"
    echo -e "${YELLOW}Please use Azure Portal or Azure CLI with proper configuration${NC}"
}

deploy_function() {
    local provider=$1
    local func_name=$2
    
    if [ ! -d "$func_name" ]; then
        echo -e "${RED}❌ Function directory $func_name not found${NC}"
        exit 1
    fi
    
    case $provider in
        aws)
            deploy_aws_lambda "$func_name"
            ;;
        gcp)
            deploy_gcp_function "$func_name"
            ;;
        azure)
            deploy_azure_function "$func_name"
            ;;
        *)
            echo -e "${RED}❌ Unknown provider: $provider${NC}"
            exit 1
            ;;
    esac
}

main() {
    if [ $# -lt 1 ]; then
        usage
        exit 1
    fi
    
    local provider=$1
    local target=${2:-all}
    
    print_banner
    
    check_dependencies "$provider"
    test_functions
    
    if [ "$target" = "all" ]; then
        echo -e "${BLUE}📦 Deploying all functions to $provider...${NC}"
        for func in "${FUNCTIONS[@]}"; do
            deploy_function "$provider" "$func"
        done
    else
        deploy_function "$provider" "$target"
    fi
    
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║                      🎉 Deployment Complete! 🎉                         ║"
    echo "║                                                                          ║"
    echo "║  SafeHer cloud functions are now live and ready for production!         ║"
    echo "║                                                                          ║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

main "$@"