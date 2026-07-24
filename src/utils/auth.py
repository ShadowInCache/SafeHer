"""
SafeHer Authentication System
JWT-based authentication with user management
"""

import jwt
import bcrypt
import logging
from datetime import datetime, timedelta
from functools import wraps
from flask import request, jsonify
import os
from typing import Optional, Dict

# Configure logging
logger = logging.getLogger(__name__)

# JWT Configuration (must be provided by environment for security)
JWT_SECRET = os.getenv('JWT_SECRET_KEY')
if not JWT_SECRET:
    raise RuntimeError("JWT_SECRET_KEY must be set for authentication")

JWT_ALGORITHM = os.getenv('JWT_ALGORITHM', 'HS256')
JWT_EXPIRATION_HOURS = int(os.getenv('JWT_EXPIRATION_HOURS', '24'))


class AuthManager:
    """Manages authentication and authorization"""
    
    @staticmethod
    def hash_password(password: str) -> str:
        """Hash a password using bcrypt"""
        salt = bcrypt.gensalt()
        return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')
    
    @staticmethod
    def verify_password(password: str, hashed: str) -> bool:
        """Verify a password against its hash"""
        return bcrypt.checkpw(password.encode('utf-8'), hashed.encode('utf-8'))
    
    @staticmethod
    def generate_token(user_id: str, email: str, role: str = 'user') -> str:
        """Generate a JWT token"""
        expiration = datetime.utcnow() + timedelta(hours=JWT_EXPIRATION_HOURS)
        
        payload = {
            'user_id': user_id,
            'email': email,
            'role': role,
            'exp': expiration,
            'iat': datetime.utcnow(),
            'type': 'access'
        }
        
        return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
    
    @staticmethod
    def decode_token(token: str) -> Optional[Dict]:
        """Decode and verify a JWT token"""
        try:
            payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
            return payload
        except jwt.ExpiredSignatureError:
            return None  # Token expired
        except jwt.InvalidTokenError:
            return None  # Invalid token
    
    @staticmethod
    def generate_refresh_token(user_id: str) -> str:
        """Generate a refresh token (longer expiration)"""
        expiration = datetime.utcnow() + timedelta(days=30)
        
        payload = {
            'user_id': user_id,
            'exp': expiration,
            'iat': datetime.utcnow(),
            'type': 'refresh'
        }
        
        return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def require_auth(f):
    """Decorator to require authentication for routes"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Get token from Authorization header
        auth_header = request.headers.get('Authorization')
        
        if not auth_header:
            return jsonify({
                'error': 'Missing authorization header',
                'message': 'Please provide a valid JWT token'
            }), 401
        
        # Extract token (format: "Bearer <token>")
        try:
            token = auth_header.split(' ')[1]
        except IndexError:
            return jsonify({
                'error': 'Invalid authorization header',
                'message': 'Format should be: Bearer <token>'
            }), 401
        
        # Verify token
        payload = AuthManager.decode_token(token)
        
        if not payload:
            return jsonify({
                'error': 'Invalid or expired token',
                'message': 'Please login again'
            }), 401
        
        # Add user info to request
        request.current_user = payload
        
        return f(*args, **kwargs)
    
    return decorated_function


def require_role(role: str):
    """Decorator to require specific role"""
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            # First check authentication
            auth_header = request.headers.get('Authorization')
            
            if not auth_header:
                return jsonify({
                    'error': 'Missing authorization header'
                }), 401
            
            try:
                token = auth_header.split(' ')[1]
            except IndexError:
                return jsonify({
                    'error': 'Invalid authorization header'
                }), 401
            
            payload = AuthManager.decode_token(token)
            
            if not payload:
                return jsonify({
                    'error': 'Invalid or expired token'
                }), 401
            
            # Check role
            if payload.get('role') != role:
                return jsonify({
                    'error': 'Insufficient permissions',
                    'message': f'This endpoint requires {role} role'
                }), 403
            
            request.current_user = payload
            
            return f(*args, **kwargs)
        
        return decorated_function
    return decorator


def optional_auth(f):
    """Decorator that adds user info if authenticated, but doesn't require it"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        
        if auth_header:
            try:
                token = auth_header.split(' ')[1]
                payload = AuthManager.decode_token(token)
                if payload:
                    request.current_user = payload
            except IndexError:
                logger.warning("Invalid token format in Auth header")
            except Exception as e:
                logger.error(f"Token validation error: {str(e)}")
        
        return f(*args, **kwargs)
    
    return decorated_function
