"""
Core event processing logic
"""

import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

class EventProcessor:
    """Process and analyze security events"""
    
    def __init__(self):
        self.event_handlers = {}
        
    def register_handler(self, event_type: str, handler):
        """Register a handler for an event type"""
        self.event_handlers[event_type] = handler
        
    def process(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Process an event"""
        event_type = event.get('type', 'unknown')
        
        if event_type in self.event_handlers:
            return self.event_handlers[event_type](event)
        
        logger.warning(f"No handler for event type: {event_type}")
        return {'status': 'unknown', 'event': event}
