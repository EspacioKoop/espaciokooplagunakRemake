"""Validated deployment settings. Access keys are never placed in argv or JSON config."""
from pathlib import Path
import os

class ConfigError(ValueError):
    pass

def integer(env, name, default, low, high):
    value = env.get(name, str(default))
    try:
        number = int(value)
    except (ValueError, TypeError):
        raise ConfigError(f"{name} must be an integer") from None
    if str(number) != value or not low <= number <= high:
        raise ConfigError(f"{name} is outside its supported range")
    return number

def read_key(path):
    key_file = Path(path)
    if not key_file.is_absolute() or not key_file.is_file():
        raise ConfigError("LAGUNAK_KEY_FILE must name a readable absolute file")
    try:
        with key_file.open("rb") as source:
            raw = source.read(132)
    except OSError:
        raise ConfigError("Cannot read LAGUNAK_KEY_FILE") from None
    if len(raw) > 130:
        raise ConfigError("The access key file is too large")
    raw = raw.rstrip(b"\r\n")
    if not 16 <= len(raw) <= 128 or any(byte < 33 or byte > 126 for byte in raw):
        raise ConfigError("The access key must contain 16–128 visible ASCII characters")
    return raw.decode("ascii")

def configuration(env=None):
    env = os.environ if env is None else env
    key_path = env.get("LAGUNAK_KEY_FILE", "")
    read_key(key_path)
    load_mode = env.get("LAGUNAK_LOAD_MODE", "auto")
    if load_mode not in {"auto", "resume", "new"}:
        raise ConfigError("LAGUNAK_LOAD_MODE must be auto, resume or new")
    return {"version": 1, "port": integer(env, "LAGUNAK_PORT", 27840, 1024, 65535),
            "mission_index": integer(env, "LAGUNAK_MISSION_INDEX", -1, -1, 255),
            "load_mode": load_mode, "key_file": str(Path(key_path))}
