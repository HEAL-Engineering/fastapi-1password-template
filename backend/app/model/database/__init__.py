"""
Database Models Package

Import all models here so they are registered with SQLAlchemy's Base.metadata.
This is required for create_all() and Alembic migrations to discover models.
"""

from app.model.database.greeting import Greeting

__all__ = ["Greeting"]
