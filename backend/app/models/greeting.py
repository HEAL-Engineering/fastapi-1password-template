"""
Greeting Database Model

This model demonstrates the standard SQLAlchemy 2.0+ patterns used in this template.
Use this as a reference when creating your own models.

KEY PATTERNS:
- Mapped[Type] for type-safe column definitions
- mapped_column() for column configuration
- BigInteger primary keys for PostgreSQL scalability
- Timestamp columns with server defaults
- Proper nullable handling with Type | None

TO CREATE YOUR OWN MODEL:
1. Copy this file and rename to your_model.py
2. Update __tablename__ to your table name
3. Define columns following the patterns below
4. Import in backend/app/model/database/__init__.py
5. Create a corresponding DAO in backend/app/dao/daos/
"""

from datetime import datetime

from sqlalchemy import BigInteger, DateTime, String, Text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.database.connection import Base


class Greeting(Base):
    """
    Example model representing a greeting message.

    This demonstrates:
    - Primary key with BigInteger (better for distributed systems)
    - String columns with length limits
    - Text columns for unlimited length
    - Timestamp columns with automatic defaults
    - Nullable vs required fields
    """

    __tablename__ = "greeting"

    # Primary key - BigInteger scales better than Integer for PostgreSQL
    id: Mapped[int] = mapped_column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    # Required string field with max length
    name: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
        index=True,  # Add index for frequently queried fields
    )

    # Required text field (unlimited length)
    message: Mapped[str] = mapped_column(
        Text,
        nullable=False,
    )

    # Optional string field (nullable)
    source: Mapped[str | None] = mapped_column(
        String(100),
        nullable=True,
    )

    # Automatic timestamp - set on insert
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    # Automatic timestamp - updated on every change
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )
