from typing import Dict, Set, Any


class SecureStore:
    def __init__(self):
        self.store: Dict[str, str] = {}
        self.groups: Dict[str, Set[str]] = {}

    def put(self, key: str, value: str, group: str) -> Dict[str, Any]:
        # Check if key already exists in the specified group
        if key in self.store and group in self.groups.get(key, set()):
            self.store[key] = value
            return {"status": "updated", "key": key, "group": group}
        else:
            self.store[key] = value
            if key in self.groups:
                self.groups[key].add(group)
            else:
                self.groups[key] = {group}
            return {"status": "created", "key": key, "group": group}

    def get(self, key: str, group: str) -> Dict[str, Any]:
        if key not in self.store:
            return {"status": "error", "message": f"Key '{key}' not found"}
        if group in self.groups.get(key, set()):
            return {"status": "success", "key": key, "value": self.store[key], "group": group}
        return {"status": "error", "message": f"Group {group} does not contain key {key}"}
