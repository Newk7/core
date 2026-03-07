import os
from datetime import datetime, timezone


class Lg:
    """
    A basic logger that prints to stdout with optional color support.

    Disable colors with ``export COLORS_ENABLED=0`` (colors are enabled by default).
    """

    def __init__(self, name="lg", colors_enabled: bool = None):
        self.name = name
        self.colors_enabled = colors_enabled
        if self.colors_enabled is None:
            self.colors_enabled = os.getenv('COLORS_ENABLED', '1') == '1'

    def log(self, level, message):
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        color_codes = {
            'warning': '\033[33m',
            'error': '\033[31m',
            'critical': '\033[31m',
            'debug': '\033[1;37m',
        }
        color = color_codes.get(level.lower())
        if color and self.colors_enabled:
            print(f"{color}{timestamp} - {self.name} - {level} - {message}\033[0m", flush=True)
        else:
            print(f"{timestamp} - {self.name} - {level} - {message}", flush=True)

    def debug(self, message):
        self.log("DEBUG", message)

    def info(self, message):
        self.log("INFO", message)

    def warning(self, message):
        self.log("WARNING", message)

    def error(self, message):
        self.log("ERROR", message)

    def critical(self, message):
        self.log("CRITICAL", message)


def create_log(n: str = "lg", colors: bool = True):
    return Lg(n, colors_enabled=colors)
