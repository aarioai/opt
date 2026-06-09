#!/bin/sh
set -eu

# https://github.com/aarioai/opt
if [ -x "./postgres-sql-lib.sh" ]; then . ./postgres-sql-lib.sh; else . /opt/postgres/lib/postgres-sql-lib.sh; fi

POSTGRES_DB=${POSTGRES_DB:-"postgres"}
POSTGRES_DEFAULT_SCHEMA=${POSTGRES_DEFAULT_SCHEMA:-"public"}

pgPsql(){
  Usage $# -ge 2 'pgPsql <maintainer> <database> [psql-args]...'
  _pg_maintainer="$1"
  _pg_db="$2"
  shift 2
  psql -v ON_ERROR_STOP=1 --username "$_pg_maintainer" --dbname "$_pg_db" "$@"
}
export pgPsql
readonly pgPsql

pgWaitReady(){
  Usage $# 1 4 "pgWaitReady <user> [database=$POSTGRES_DB] [timeout=30] [interval=2]"
  _pg_user="$1"
  _pg_db="${2:-"$POSTGRES_DB"}"
  _pg_timeout="${3:-30}"
  _pg_interval="${4:-2}"

  Info "pg_isready -U $_pg_user -d $_pg_db --> timeout: $_pg_timeout"
  _pg_counter=0
  _pg_max_attempts=$(((_pg_timeout + _pg_interval - 1) / _pg_interval))

  until pg_isready -U "$_pg_user" -d "$_pg_db"; do
    _pg_counter=$((_pg_counter + 1))
    if [ "$_pg_counter" -ge "$_pg_max_attempts" ]; then
      PanicD "PostgreSQL connect timeout (${_pg_timeout}s)" "PostgreSQL 连接超时 (${_pg_timeout}秒)"
    fi

    DebugD 'waiting for PostgreSQL to start...' '等待PostgreSQL启动...'
    sleep "$_pg_interval"
  done
}
export pgWaitReady
readonly pgWaitReady

pgCreateExtensions(){
  Usage $# -ge 3 'pgCreateExtensions <maintainer> <database> <extension> [extension]...'
  _pg_maintainer="$1"
  _pg_db="$2"
  shift 2

  for _pg_ext in "$@"; do
    Info "create extension $_pg_ext in $_pg_db"
    pgPsql "$_pg_maintainer" "$_pg_db" -c "CREATE EXTENSION IF NOT EXISTS \"$_pg_ext\";" >/dev/null
  done
}
export pgCreateExtensions
readonly pgCreateExtensions

pgDbRoleExists(){
  Usage $# 2 3 "pgDbRoleExists <rolname> <maintainer> [database=$POSTGRES_DB]"
  _pg_rolname="$1"
  _pg_maintainer="$2"
  _pg_db="${3:-"$POSTGRES_DB"}"

  pgPsql "$_pg_maintainer" "$_pg_db" -tAc "SELECT 1 FROM pg_roles WHERE rolname='$_pg_rolname';" 2>/dev/null | grep -q 1
}
export pgDbRoleExists
readonly pgDbRoleExists

pgDbExists(){
  Usage $# 2 3 "pgDbExists <database> <maintainer> [maintainer_db=$POSTGRES_DB]"
  _pg_db="$1"
  _pg_maintainer="$2"
  _pg_maintainer_db="${3:-"$POSTGRES_DB"}"

  pgPsql "$_pg_maintainer" "$_pg_maintainer_db" -tAc "SELECT 1 FROM pg_database WHERE datname='$_pg_db';" 2>/dev/null | grep -q 1
}
export pgDbExists
readonly pgDbExists

pgDbEnsureLoginRole(){
  Usage $# -eq 4 'pgDbEnsureLoginRole <database> <user> <password> <maintainer>'
  _pg_db="$1"
  _pg_user="$2"
  _pg_password="$3"
  _pg_maintainer="$4"

  PanicIfEmpty "$_pg_user" 'username'

  if pgDbRoleExists "$_pg_maintainer" "$_pg_db" "$_pg_user"; then
    return
  fi
  Info "create user $_pg_user"
  PanicIfEmpty "$_pg_password" 'password'
  pgPsql "$_pg_maintainer" "$_pg_db" -c "CREATE USER $_pg_user WITH PASSWORD '$_pg_password';" >/dev/null
}
export pgDbEnsureLoginRole
readonly pgDbEnsureLoginRole

pgRoleInherit(){
  Usage $# -eq 4 'pgRoleInherit <parent_role> <child_role> <db> <maintainer>'
  _pg_parent_role="$1"
  _pg_child_role="$2"
  _pg_db="$3"
  _pg_maintainer="$4"

  pgPsql "$_pg_maintainer" "$_pg_db" -c "GRANT $_pg_parent_role TO $_pg_child_role;" >/dev/null
}
export pgRoleInherit
readonly pgRoleInherit

pgDbGrantAllOnSchema(){
  Usage $# 4 5 'pgDbGrantAllOnSchema <maintainer> <user> <database> <schema> [role_prefix=_<database>]'
  _pg_maintainer="$1"
  _pg_user="$2"
  _pg_db="$3"
  _pg_schema="$4"
  _pg_role_prefix="${5:-"_${_pg_db}"}"

  _pg_owner="${_pg_role_prefix}_owner"
  _pg_reader="${_pg_role_prefix}_reader"
  _pg_writer="${_pg_role_prefix}_writer"

  Info "ensure roles: $_pg_owner, $_pg_reader, $_pg_writer"
  pgDbCreateSchemaRolesSQL "$_pg_user" "$_pg_db" "$_pg_schema" "$_pg_role_prefix" | pgPsql "$_pg_maintainer" "$_pg_db" >/dev/null
  Info "grant privileges on ${_pg_db}.${_pg_schema} to roles: $_pg_owner, $_pg_reader, $_pg_writer"
  pgDbGrantAllOnSchemaSQL "$_pg_user" "$_pg_db" "$_pg_schema" "$_pg_role_prefix" | pgPsql "$_pg_maintainer" "$_pg_db" >/dev/null
}
export pgDbGrantAllOnSchema
readonly pgDbGrantAllOnSchema

pgDbCreateSchemaOwner(){
  Usage $# -eq 5 'pgDbCreateSchemaOwner <user> <password> <database> <schema> <maintainer>'
  _pg_user="$1"
  _pg_password="$2"
  _pg_db="$3"
  _pg_schema="$4"
  _pg_maintainer="$5"

  _pg_role_prefix="_${_pg_schema}"

  pgDbEnsureLoginRole "$_pg_db" "$_pg_user" "$_pg_password" "$_pg_maintainer"
  Info "create schema ${_pg_db}.${_pg_schema}"
  pgDbCreateSchemaSQL "$_pg_schema" "$_pg_user" | pgPsql "$_pg_maintainer" "$_pg_db" >/dev/null
  pgDbGrantAllOnSchema "$_pg_maintainer" "$_pg_user" "$_pg_db" "$_pg_schema" "$_pg_role_prefix"
}
export pgDbCreateSchemaOwner
readonly pgDbCreateSchemaOwner

pgGrantDbOwner(){
  Usage $# 4 6 "pgGrantDbOwner <user> <password> <database> <maintainer> [maintainer_db=$POSTGRES_DB] [default_schema=$POSTGRES_DEFAULT_SCHEMA]"
  _pg_user="$1"
  _pg_password="$2"
  _pg_db="$3"
  _pg_maintainer="$4"
  _pg_maintainer_db="${5:-"$POSTGRES_DB"}"
  _pg_default_schema="${6:-"$POSTGRES_DEFAULT_SCHEMA"}"

  pgDbEnsureLoginRole "$_pg_maintainer_db" "$_pg_user" "$_pg_password" "$_pg_maintainer"
  if [ -n "$_pg_default_schema" ]; then
    pgDbGrantAllOnSchema "$_pg_maintainer" "$_pg_user" "$_pg_db" "$_pg_default_schema"
  fi
}
export pgGrantDbOwner
readonly pgGrantDbOwner

pgCreateDbOwner(){
  Usage $# 4 6 "pgCreateDbOwner <user> <password> <database> <maintainer> [maintainer_db=$POSTGRES_DB] [default_schema=$POSTGRES_DEFAULT_SCHEMA]"
  _pg_user="$1"
  _pg_password="$2"
  _pg_db="$3"
  _pg_maintainer="$4"
  _pg_maintainer_db="${5:-"$POSTGRES_DB"}"
  _pg_default_schema="${6:-"$POSTGRES_DEFAULT_SCHEMA"}"

  if pgDbExists "$_pg_db" "$_pg_maintainer" "$_pg_maintainer_db"; then
    pgGrantDbOwner "$_pg_user" "$_pg_password" "$_pg_db" "$_pg_maintainer" "$_pg_maintainer_db" "$_pg_default_schema"
    return
  fi

  pgDbEnsureLoginRole "$_pg_maintainer_db" "$_pg_user" "$_pg_password" "$_pg_maintainer"
  pgCreateDbSQL "$_pg_db" "$_pg_user" | pgPsql "$_pg_maintainer" "$_pg_maintainer_db" >/dev/null
  if [ -n "$_pg_default_schema" ]; then
    pgDbGrantAllOnSchema "$_pg_maintainer" "$_pg_user" "$_pg_db" "$_pg_default_schema"
  fi
}
export pgCreateDbOwner
readonly pgCreateDbOwner