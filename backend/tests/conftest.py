"""
Pytest configuration and fixture imports.

This file automatically imports all fixtures from tests/common/fixtures.py,
making them available to all test files without explicit imports.
"""

from tests.common.fixtures import *  # noqa: F401, F403
