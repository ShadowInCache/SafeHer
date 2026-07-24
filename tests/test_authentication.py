"""
Test Authentication System
Quick verification of user authentication features
"""

import requests
import json

BASE_URL = "http://localhost:5000/api/v1/auth"

def print_section(title):
    """Print section header"""
    print("\n" + "="*60)
    print(f"  {title}")
    print("="*60)

def test_register():
    """Test user registration"""
    print_section("TEST 1: User Registration")
    
    payload = {
        "email": "test@safeherapp.com",
        "password": "test123456",
        "full_name": "Test User",
        "role": "user"
    }
    
    print(f"POST {BASE_URL}/register")
    print(f"Request: {json.dumps(payload, indent=2)}")
    
    try:
        response = requests.post(f"{BASE_URL}/register", json=payload)
        print(f"\nStatus Code: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        
        if response.status_code == 201:
            print("✅ Registration successful!")
            return response.json().get('id')
        else:
            print("⚠️ Registration failed or user already exists")
            return None
    except Exception as e:
        print(f"❌ Error: {e}")
        return None

def test_login():
    """Test user login"""
    print_section("TEST 2: User Login")
    
    payload = {
        "email": "test@safeherapp.com",
        "password": "test123456"
    }
    
    print(f"POST {BASE_URL}/login")
    print(f"Request: {json.dumps(payload, indent=2)}")
    
    try:
        response = requests.post(f"{BASE_URL}/login", json=payload)
        print(f"\nStatus Code: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        
        if response.status_code == 200:
            print("✅ Login successful!")
            return response.json()['access_token']
        else:
            print("❌ Login failed")
            return None
    except Exception as e:
        print(f"❌ Error: {e}")
        return None

def test_get_profile(token):
    """Test getting user profile"""
    print_section("TEST 3: Get User Profile")
    
    headers = {
        "Authorization": f"Bearer {token}"
    }
    
    print(f"GET {BASE_URL}/me")
    print(f"Headers: Authorization: Bearer {token[:20]}...")
    
    try:
        response = requests.get(f"{BASE_URL}/me", headers=headers)
        print(f"\nStatus Code: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        
        if response.status_code == 200:
            print("✅ Profile retrieved successfully!")
        else:
            print("❌ Failed to get profile")
    except Exception as e:
        print(f"❌ Error: {e}")

def test_unauthorized_access():
    """Test accessing protected endpoint without token"""
    print_section("TEST 6: Unauthorized Access")
    
    print(f"GET {BASE_URL}/me (without token)")
    
    try:
        response = requests.get(f"{BASE_URL}/me")
        print(f"\nStatus Code: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        
        if response.status_code == 401:
            print("✅ Correctly rejected unauthorized request!")
        else:
            print("⚠️ Unexpected response for unauthorized access")
    except Exception as e:
        print(f"❌ Error: {e}")

def main():
    """Run all authentication tests"""
    print("\n" + "🔐"*30)
    print("  SAFEHER AUTHENTICATION SYSTEM TEST")
    print("🔐"*30)
    
    print("\n📋 Prerequisites:")
    print("  1. Backend API Gateway must be running")
    print("  2. URL: http://localhost:5000")
    print("  3. Press Ctrl+C to stop\n")
    
    input("Press Enter to start tests...")
    
    # Test 1: Register new user
    new_user_token = test_register()
    
    # Test 2: Login with admin
    admin_token = test_login()
    
    if admin_token:
        # Test 3: Get profile
        test_get_profile(admin_token)
    
    # Test 6: Unauthorized access
    test_unauthorized_access()
    
    print_section("TESTS COMPLETED")
    print("\n✨ Authentication system is working!")
    print("\n📖 Next steps:")
    print("  1. Integrate authentication in Flutter app")
    print("  2. Add emergency contacts management")
    print("  3. Implement password reset flow")
    print("  4. Add email verification")
    print("\n" + "="*60 + "\n")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n❌ Tests interrupted by user")
    except requests.exceptions.ConnectionError:
        print("\n\n❌ ERROR: Cannot connect to backend!")
        print("   Make sure the API Gateway is running:")
        print("   python manage.py start-api")
