#!/usr/bin/python3
"""Use /usr/bin/python3, alias k, one argument, and 'Open stdout URL'."""
import sys
from urllib.parse import urlencode

print("https://example.com/?" + urlencode({"log_stream": sys.argv[1]}))
