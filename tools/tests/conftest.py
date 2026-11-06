"""Put `tools/` on the import path, so pytest can import the checker script."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
