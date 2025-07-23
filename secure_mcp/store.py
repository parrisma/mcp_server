from typing import Dict, Set

class SecureStore:
    def __init__(self):
        self.store: Dict[str, str] = {}
        self.groups: Dict[str, Set[str]] = {}

    def put(self, key: str, value: str, group: str):
        self.store[key] = value
        self.groups[key] = {group}

    def get(self, key: str, group: str) -> str:
        if key not in self.store:
            return "Key not found"
        if group in self.groups.get(key, set()):
            return self.store[key]
        return "Access denied"