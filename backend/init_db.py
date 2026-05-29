#!/usr/bin/env python3
"""
Bootstrap the database schema for local dev.

Runs Base.metadata.create_all() via app.database.connection.init_db().
Idempotent — only creates tables that don't already exist. Intended
to be invoked once per container start; the FastAPI app does not call
this on startup (keeps boot fast and avoids races between workers).

For production schema changes, replace with Alembic migrations.
"""

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.core.config import settings
from app.database.connection import init_db

logger = settings.logger


async def main() -> None:
    logger.info("Bootstrapping database schema (create_all)...")
    await init_db()
    logger.info("Schema ready")


if __name__ == "__main__":
    asyncio.run(main())
