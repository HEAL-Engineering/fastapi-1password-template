#!/usr/bin/env bash
set -e

# =============================================================================
# CONFIGURATION - Modify these variable prefixes for your project
# Change APP_ to YOUR_PROJECT_ to match your naming convention
# =============================================================================

# PostgreSQL initialization script for creating databases
# This script is automatically executed when PostgreSQL container starts
#
# Environment-aware behavior:
# - PRODUCTION: Creates only the database specified in APP_DB_NAME (or DB_NAME)
# - TEST/DEV: Creates dev, test, and optionally pytest databases
#
# SECURITY: This script uses bash variable interpolation into SQL.
# Input validation is performed to prevent SQL injection from malformed
# environment variables. Variables must come from trusted sources only.

echo "=== PostgreSQL Database Initialization ==="

# Check if we're running as the postgres superuser
if [ "$POSTGRES_USER" != "postgres" ]; then
    echo "ERROR: This script must be run with POSTGRES_USER=postgres"
    exit 1
fi

# Detect environment (check multiple common env var names)
ENVIRONMENT="${ENVIRONMENT:-${ENV:-local}}"
echo "🌍 Environment detected: $ENVIRONMENT"

# Function to create a database and user
create_database() {
    local db_name=$1
    local db_user=$2
    local db_password=$3

    # Validate inputs to prevent SQL injection
    # Database/user names must be alphanumeric with underscores/hyphens only
    if [[ ! "$db_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "ERROR: Invalid database name '$db_name' (must be alphanumeric with _- only)"
        exit 1
    fi
    if [[ ! "$db_user" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "ERROR: Invalid user name '$db_user' (must be alphanumeric with _- only)"
        exit 1
    fi
    # Password can contain more characters, but check for single quotes which would break SQL
    if [[ "$db_password" == *"'"* ]]; then
        echo "ERROR: Password cannot contain single quotes"
        exit 1
    fi

    echo "Creating database: $db_name"
    echo "Creating user: $db_user"

    psql -v ON_ERROR_STOP=1 <<-EOSQL
        -- Check if user exists, create if not
        DO
        \$\$
        BEGIN
            IF NOT EXISTS (
                SELECT FROM pg_catalog.pg_user
                WHERE usename = '$db_user'
            ) THEN
                CREATE USER "$db_user" WITH PASSWORD '$db_password';
            END IF;
        END
        \$\$;

        -- Check if database exists, create if not
        SELECT 'CREATE DATABASE "$db_name"'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db_name')\gexec

        -- Grant all privileges
        GRANT ALL PRIVILEGES ON DATABASE "$db_name" TO "$db_user";

        -- Connect to the new database and grant schema privileges
        \c "$db_name"
        GRANT ALL ON SCHEMA public TO "$db_user";
        ALTER DATABASE "$db_name" OWNER TO "$db_user";
EOSQL

    echo "✓ Database '$db_name' created with owner '$db_user'"
}

# Read environment variables or use defaults
APP_DB_USER="${APP_DB_USER:-app_user}"
APP_DB_PASSWORD="${APP_DB_PASSWORD:-app_pass}"

# Production vs Dev/Test behavior
if [ "$ENVIRONMENT" = "prod" ] || [ "$ENVIRONMENT" = "production" ]; then
    echo "🔴 PRODUCTION MODE: Creating single production database only"

    # In production, create only the database specified in APP_DB_NAME or DB_NAME
    PROD_DB_NAME="${APP_DB_NAME:-${DB_NAME:-app_db_prod}}"

    echo "📦 Production database name: $PROD_DB_NAME"
    create_database "$PROD_DB_NAME" "$APP_DB_USER" "$APP_DB_PASSWORD"

    echo ""
    echo "=== Database Initialization Complete ==="
    echo "🔴 Production database: $PROD_DB_NAME"
    echo "   User: $APP_DB_USER"
    echo "   Connection: postgresql+psycopg://$APP_DB_USER:$APP_DB_PASSWORD@localhost:5432/$PROD_DB_NAME"
    echo "   Host: localhost (or postgres container name)"
    echo "   Port: 5432"
    echo ""
    echo "ℹ️  Only production database created (no dev/test databases in production)"
    echo "====================================="
else
    echo "🟢 DEV/TEST MODE: Creating multiple databases for development"

    # Main development database (from environment or default)
    DEV_DB_NAME="${APP_DB_NAME:-app_db}"
    # Test database (from environment or default)
    DEV_TEST_DB_NAME="${APP_TEST_DB_NAME:-app_db_test}"

    # Create main development database
    create_database "$DEV_DB_NAME" "$APP_DB_USER" "$APP_DB_PASSWORD"

    # Create test database (same user, different database)
    create_database "$DEV_TEST_DB_NAME" "$APP_DB_USER" "$APP_DB_PASSWORD"

    # Create pytest database (for automated tests) - only if TEST_DB_NAME is set
    if [ -n "$TEST_DB_NAME" ]; then
        TEST_DB_USER="${TEST_DB_USER:-$APP_DB_USER}"
        TEST_DB_PASSWORD="${TEST_DB_PASSWORD:-$APP_DB_PASSWORD}"

        echo "Creating pytest database for automated testing..."
        create_database "$TEST_DB_NAME" "$TEST_DB_USER" "$TEST_DB_PASSWORD"

        PYTEST_INFO="Pytest database: $TEST_DB_NAME
User: $APP_DB_USER (dev/test), $TEST_DB_USER (pytest)

Connection strings:
  Development: postgresql+psycopg://$APP_DB_USER:$APP_DB_PASSWORD@localhost:5432/$DEV_DB_NAME
  Test:        postgresql+psycopg://$APP_DB_USER:$APP_DB_PASSWORD@localhost:5432/$DEV_TEST_DB_NAME
  Pytest:      postgresql+psycopg://$TEST_DB_USER:$TEST_DB_PASSWORD@localhost:5432/$TEST_DB_NAME"
    else
        PYTEST_INFO="User: $APP_DB_USER

Connection strings:
  Development: postgresql+psycopg://$APP_DB_USER:$APP_DB_PASSWORD@localhost:5432/$DEV_DB_NAME
  Test:        postgresql+psycopg://$APP_DB_USER:$APP_DB_PASSWORD@localhost:5432/$DEV_TEST_DB_NAME"
    fi

    echo ""
    echo "=== Database Initialization Complete ==="
    echo "🟢 Development database: $DEV_DB_NAME"
    echo "🟢 Test database: $DEV_TEST_DB_NAME"
    echo "$PYTEST_INFO"
    echo "Host: localhost (or postgres container name)"
    echo "Port: 5432"
    echo ""
    echo "====================================="
fi
