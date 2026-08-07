"""
User Management System
Handles user registration, login, profile management
"""

from datetime import datetime
import uuid
from typing import Optional, Dict, List
import logging

logger = logging.getLogger(__name__)


class User:
    """User model"""
    
    def __init__(self, user_id: str, email: str, password_hash: str, 
                 full_name: str, phone_number: Optional[str] = None,
                 role: str = 'user', created_at: Optional[datetime] = None):
        self.user_id = user_id
        self.email = email
        self.password_hash = password_hash
        self.full_name = full_name
        self.phone_number = phone_number
        self.role = role
        self.created_at = created_at or datetime.utcnow()
        self.updated_at = datetime.utcnow()
        self.is_active = True
        self.email_verified = False
        self.emergency_contacts = []
    
    def to_dict(self, include_sensitive=False):
        """Convert user to dictionary"""
        data = {
            'user_id': self.user_id,
            'email': self.email,
            'full_name': self.full_name,
            'phone_number': self.phone_number,
            'role': self.role,
            'is_active': self.is_active,
            'email_verified': self.email_verified,
            'created_at': self.created_at.isoformat(),
            'updated_at': self.updated_at.isoformat()
        }
        
        if include_sensitive:
            data['password_hash'] = self.password_hash
        
        return data


class UserManager:
    """Manages user operations (in-memory for now, replace with database)"""
    
    def __init__(self):
        # In-memory user storage (replace with database in production)
        self.users: Dict[str, User] = {}
        self.email_index: Dict[str, str] = {}  # email -> user_id mapping
        
        # Create default admin user
        self._create_default_admin()
    
    def _create_default_admin(self):
        """Create default admin user for development"""
        from .auth import AuthManager
        
        admin_id = 'admin_' + str(uuid.uuid4())
        admin_password_hash = AuthManager.hash_password('admin123')
        
        admin = User(
            user_id=admin_id,
            email='admin@safeher.local',
            password_hash=admin_password_hash,
            full_name='System Administrator',
            phone_number='+15555555555',
            role='admin'
        )
        admin.email_verified = True
        
        self.users[admin_id] = admin
        self.email_index['admin@safeher.local'] = admin_id
        
        logger.info("✅ Default admin user created: admin@safeher.local / admin123")
    
    def create_user(self, email: str, password: str, full_name: str, 
                   phone_number: Optional[str] = None, role: str = 'user') -> Optional[User]:
        """Create a new user"""
        from .auth import AuthManager
        
        # Check if email already exists
        if email in self.email_index:
            logger.warning(f"User registration failed: Email {email} already exists")
            return None
        
        # Create user
        user_id = 'user_' + str(uuid.uuid4())
        password_hash = AuthManager.hash_password(password)
        
        user = User(
            user_id=user_id,
            email=email,
            password_hash=password_hash,
            full_name=full_name,
            phone_number=phone_number,
            role=role
        )
        
        # Store user
        self.users[user_id] = user
        self.email_index[email] = user_id
        
        logger.info(f"✅ User created: {email} ({user_id})")
        
        return user
    
    def get_user_by_id(self, user_id: str) -> Optional[User]:
        """Get user by ID"""
        return self.users.get(user_id)
    
    def get_user_by_email(self, email: str) -> Optional[User]:
        """Get user by email"""
        user_id = self.email_index.get(email)
        if user_id:
            return self.users.get(user_id)
        return None
    
    def authenticate(self, email: str, password: str) -> Optional[User]:
        """Authenticate user with email and password"""
        from .auth import AuthManager
        
        user = self.get_user_by_email(email)
        
        if not user:
            logger.warning(f"Login failed: User {email} not found")
            return None
        
        if not user.is_active:
            logger.warning(f"Login failed: User {email} is inactive")
            return None
        
        if not AuthManager.verify_password(password, user.password_hash):
            logger.warning(f"Login failed: Invalid password for {email}")
            return None
        
        logger.info(f"✅ User authenticated: {email}")
        return user
    
    def update_user(self, user_id: str, **kwargs) -> Optional[User]:
        """Update user information"""
        user = self.get_user_by_id(user_id)
        
        if not user:
            return None
        
        # Update allowed fields
        allowed_fields = ['full_name', 'phone_number', 'email_verified', 'is_active']
        
        for field, value in kwargs.items():
            if field in allowed_fields:
                setattr(user, field, value)
        
        user.updated_at = datetime.utcnow()
        
        logger.info(f"✅ User updated: {user.email}")
        
        return user
    
    def change_password(self, user_id: str, old_password: str, new_password: str) -> bool:
        """Change user password"""
        from .auth import AuthManager
        
        user = self.get_user_by_id(user_id)
        
        if not user:
            return False
        
        # Verify old password
        if not AuthManager.verify_password(old_password, user.password_hash):
            logger.warning(f"Password change failed: Invalid old password for {user.email}")
            return False
        
        # Update password
        user.password_hash = AuthManager.hash_password(new_password)
        user.updated_at = datetime.utcnow()
        
        logger.info(f"✅ Password changed for: {user.email}")
        
        return True
    
    def delete_user(self, user_id: str) -> bool:
        """Delete user (soft delete)"""
        user = self.get_user_by_id(user_id)
        
        if not user:
            return False
        
        user.is_active = False
        user.updated_at = datetime.utcnow()
        
        logger.info(f"✅ User deactivated: {user.email}")
        
        return True
    
    def get_all_users(self) -> List[User]:
        """Get all users (admin only)"""
        return list(self.users.values())
    
    def add_emergency_contact(self, user_id: str, contact: Dict) -> bool:
        """Add emergency contact for user"""
        user = self.get_user_by_id(user_id)
        
        if not user:
            return False
        
        contact['contact_id'] = str(uuid.uuid4())
        contact['created_at'] = datetime.utcnow().isoformat()
        
        user.emergency_contacts.append(contact)
        user.updated_at = datetime.utcnow()
        
        logger.info(f"✅ Emergency contact added for: {user.email}")
        
        return True
    
    def get_emergency_contacts(self, user_id: str) -> List[Dict]:
        """Get emergency contacts for user"""
        user = self.get_user_by_id(user_id)
        
        if not user:
            return []
        
        return user.emergency_contacts


# Global user manager instance
user_manager = UserManager()
