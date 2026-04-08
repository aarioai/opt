#!/bin/sh
set -eu

. /opt/aa/lib/aa-posix-lib.sh

POSTGRES_USER=${POSTGRES_USER:-postgres}

# 等待 PostgreSQL ready
pgUntilReady(){
    Info "pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"

    _timeout="${1:-30}"
    _interval=2
    _count=0
    _max_attempts=$((_timeout / _interval))

    until pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"; do
        _counter=$((_counter + 1))
        if [ $_counter -ge $_max_attempts ]; then
            ErrorD "PostgreSQL connect timeout (${_timeout}s)" "PostgreSQL 连接超时 (${_timeout}秒)"
            exit 1
        fi

        DebugD 'waiting for PostgreSQL to start...' '等待PostgreSQL启动...'
        sleep $_interval
    done
}
readonly pgUntilReady

_pgCreateSchemaRolesSQL(){
    Usage $# 3 4 '_pgCreateSchemaRolesSQL <database> <schema> <user> [role_prefix=<database>]'
    _database="$1"
    _schema="$2"
    _user="$3"
    _role_prefix="${4:-"$_database"}"

    _owner="${_role_prefix}_owner"
    _reader="${_role_prefix}_reader"
    _writer="${_role_prefix}_writer"

    cat <<-EOSQL
        -- 需要重新连接到数据库 a_gateway
        \c $_database;
        CREATE SCHEMA IF NOT EXISTS $_schema;

        CREATE ROLE $_owner NOLOGIN;
        CREATE ROLE $_reader NOLOGIN;
        CREATE ROLE $_writer NOLOGIN;

        GRANT CONNECT, TEMPORARY ON DATABASE $_database TO $_owner, $_reader, $_writer;
        GRANT ALL PRIVILEGES ON SCHEMA $_schema TO $_owner;

        -- 继承角色，后面改动角色权限，user 也自动获取
        GRANT $_owner TO $_user
EOSQL
}
readonly _pgCreateSchemaRolesSQL

_pgGrantAllOnSchema(){
    Usage $# 3 4 '_pgGrantAllOnSchema <database> <schema> <user> [role_prefix=<database>]'
    _database="$1"
    _schema="$2"
    _user="$3"
    _role_prefix="${4:-"$_database"}"

    _owner="${_role_prefix}_owner"
    _reader="${_role_prefix}_reader"
    _writer="${_role_prefix}_writer"

    cat <<-EOSQL
        -- 需要重新连接到数据库 $_database
        \c $_database;

        -- schema 级别权限
        GRANT USAGE ON SCHEMA $_schema TO $_owner, $_reader, $_writer;
        GRANT CREATE ON SCHEMA $_schema TO $_owner;

        -- table 级别权限
        GRANT SELECT ON ALL TABLES IN SCHEMA $_schema TO $_reader;
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA $_schema TO $_writer;
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA $_schema TO $_owner;

        -- 自增ID权限
        GRANT USAGE ON ALL SEQUENCES IN SCHEMA $_schema TO $_writer, $_owner;
        GRANT SELECT ON ALL SEQUENCES IN SCHEMA $_schema TO $_reader;

        -- 存储过程、触发器等函数权限
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA $_schema TO $_writer, $_owner;
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA $_schema TO $_reader;

        -- 默认权限（对未来对象生效）
        ALTER DEFAULT PRIVILEGES FOR USER $_user IN SCHEMA $_schema GRANT SELECT ON TABLES TO $_reader;
        ALTER DEFAULT PRIVILEGES FOR USER $_user IN SCHEMA $_schema GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO $_writer;
        ALTER DEFAULT PRIVILEGES FOR USER $_user IN SCHEMA $_schema GRANT ALL PRIVILEGES ON TABLES TO $_owner;

        -- 自增ID默认权限
        ALTER DEFAULT PRIVILEGES FOR USER $_user IN SCHEMA $_schema GRANT USAGE ON SEQUENCES TO $_writer, $_owner;
        ALTER DEFAULT PRIVILEGES FOR USER $_user IN SCHEMA $_schema GRANT SELECT ON SEQUENCES TO $_reader;

        -- 函数的默认权限
        ALTER DEFAULT PRIVILEGES FOR USER $_user IN SCHEMA $_schema GRANT EXECUTE ON FUNCTIONS TO $_reader, $_writer, $_owner;
EOSQL
}
readonly _pgGrantAllOnSchema

pgGrantAllOnSchema(){
    Usage $# 3 4 'pgGrantAllOnSchema <database> <schema> <user> [role_prefix=<database>]'
    _database="$1"
    _schema="$2"
    _user="$3"
    _role_prefix="${4:-"$_database"}"

    _owner="${_role_prefix}_owner"
    _reader="${_role_prefix}_reader"
    _writer="${_role_prefix}_writer"

    Info "create roles: $_owner, $_reader, $_writer"
    _pgCreateSchemaRolesSQL "$@" | psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$_database"

    Info "grant all privileges on ${_database}.${_schema} to roles: $_owner, $_reader, $_writer"
    _pgGrantAllOnSchema "$@" | psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$_database"
}

readonly pgGrantAllOnSchema

_pgCreateSchemaSQL(){
    Usage $# -ge 4 '_pgCreateSchemaSQL <user> <password> <database> <schema> [options]...'
    _user="$1"
    _password="$2"
    _database="$3"
    _schema="$4"
    shift 4
    _options="$*"

    cat <<-EOSQL
        \c $_database;
        CREATE USER $_user WITH PASSWORD '$_password' $_options;
        CREATE SCHEMA IF NOT EXISTS $_schema;

        -- 设置用户默认schema
        ALTER USER $_user SET search_path TO $_schema;
EOSQL
}
readonly _pgCreateSchemaSQL

pgCreateSchemaOwnerSQL(){
    Usage $# -ge 4 'pgCreateSchemaOwnerSQL <user> <password> <database> <schema> [options]...'
    _user="$1"
    _password="$2"
    _database="$3"
    _schema="$4"

    # schema 角色以下划线开头
    _role_prefix="_${_schema}"

    _pgCreateSchemaSQL "$@"
    printf '\n\n'
    _pgCreateSchemaRolesSQL "$_database" "$_schema" "$_user" "$_role_prefix"
    printf '\n\n'
    _pgGrantAllOnSchema "$_database" "$_schema" "$_user" "$_role_prefix"
}
readonly pgCreateSchemaOwnerSQL

pgCreateSchemaOwner(){
    Usage $# -ge 4 'pgCreateSchemaOwner <user> <password> <database> <schema> [options]...'
    _user="$1"
    _password="$2"
    _database="$3"
    _schema="$4"

    Info "create schema ${_database}.${_schema} and its owner $_user"
    _pgCreateSchemaSQL "$@" | psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$_database"

    # schema 角色以下划线开头
    _role_prefix="_${_schema}"
    pgGrantAllOnSchema "$_database" "$_schema" "$_user" "$_role_prefix"
}
readonly pgCreateSchemaOwner


_pgCreateDatabaseOwnerSQL(){
    Usage $# -ge 3 '_pgCreateDatabaseOwnerSQL <user> <password> <database> [options]...'
    _user="$1"
    _password="$2"
    _database="$3"
    shift 3
    _options="$*"
    #  PostgreSQL 不支持 CREATE DATABASE IF NOT EXISTS，因此必须要确定创建的库不存在。
    cat <<-EOSQL
        CREATE USER $_user WITH PASSWORD '$_password' $_options;
        CREATE DATABASE $_database OWNER $_user ENCODING 'UTF8';
        GRANT ALL PRIVILEGES ON DATABASE $_database TO $_user;
EOSQL
}
readonly _pgCreateDatabaseOwnerSQL

pgCreateDatabaseOwnerSQL(){
    Usage $# -ge 3 'pgCreateDatabaseOwnerSQL <user> <password> <database> [options]...'
    _user="$1"
    _password="$2"
    _database="$3"
    _schema='public'

    _pgCreateDatabaseOwnerSQL "$@"
    printf '\n\n'
    _pgCreateSchemaRolesSQL "$_database" "$_schema" "$_user"
    printf '\n\n'
    _pgGrantAllOnSchema "$_database" "$_schema" "$_user"
}
readonly pgCreateDatabaseOwnerSQL

# 创建用户和 owner, reader, writer 角色
pgCreateDatabaseOwner(){
    Usage $# -ge 3 'pgCreateDatabaseOwner <user> <password> <database> [options]...'
    _user="$1"
    _password="$2"
    _database="$3"
    _schema='public'

    Info "create database $_database and its owner $_user"
    _pgCreateDatabaseOwnerSQL "$@" | psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"
    pgGrantAllOnSchema "$_database" "$_schema" "$_user"
}
readonly pgCreateDatabaseOwner