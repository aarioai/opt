#!/bin/sh
set -eu

# https://github.com/aarioai/opt
if [ -x "../../aa/lib/aa-posix-lib.sh" ]; then . ../../aa/lib/aa-posix-lib.sh; else . /opt/aa/lib/aa-posix-lib.sh; fi

pgCreateDbSQL(){
  Usage $# -eq 2 'pgCreateDbSQL <database> <owner>'
  _pg_db="$1"
  _pg_owner="$2"

  cat <<-EOSQL
	CREATE DATABASE $_pg_db OWNER $_pg_owner ENCODING 'UTF8';
	GRANT ALL PRIVILEGES ON DATABASE $_pg_db TO $_pg_owner;
EOSQL
}
export pgCreateDbSQL
readonly pgCreateDbSQL

pgDbCreateSchemaSQL(){
  Usage $# -eq 2 'pgDbCreateSchemaSQL <schema> <user>'
  _pg_schema="$1"
  _pg_user="$2"

  cat <<-EOSQL
	CREATE SCHEMA IF NOT EXISTS $_pg_schema;
	ALTER USER $_pg_user SET search_path TO $_pg_schema;
EOSQL
}
export pgDbCreateSchemaSQL
readonly pgDbCreateSchemaSQL

pgDbCreateSchemaRolesSQL(){
  Usage $# 3 4 'pgDbCreateSchemaRolesSQL <user> <database> <schema> [role_prefix=<database>]'
  _pg_user="$1"
  _pg_db="$2"
  _pg_schema="$3"
  _pg_role_prefix="${4:-"$_pg_db"}"

  _pg_owner="${_pg_role_prefix}_owner"
  _pg_reader="${_pg_role_prefix}_reader"
  _pg_writer="${_pg_role_prefix}_writer"

  cat <<-EOSQL
	CREATE SCHEMA IF NOT EXISTS $_pg_schema;

	DO \$\$
	BEGIN
	  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$_pg_owner') THEN
	    CREATE ROLE $_pg_owner NOLOGIN;
	  END IF;
	  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$_pg_reader') THEN
	    CREATE ROLE $_pg_reader NOLOGIN;
	  END IF;
	  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$_pg_writer') THEN
	    CREATE ROLE $_pg_writer NOLOGIN;
	  END IF;
	END
	\$\$;

	GRANT CONNECT, TEMPORARY ON DATABASE $_pg_db TO $_pg_owner, $_pg_reader, $_pg_writer;
	GRANT ALL PRIVILEGES ON SCHEMA $_pg_schema TO $_pg_owner;
	-- role inheritance: permission changes to $_pg_owner propagate to $_pg_user automatically
	GRANT $_pg_owner TO $_pg_user;
EOSQL
}
export pgDbCreateSchemaRolesSQL
readonly pgDbCreateSchemaRolesSQL

pgDbGrantAllOnSchemaSQL(){
  Usage $# 3 4 'pgDbGrantAllOnSchemaSQL <user> <database> <schema> [role_prefix=<database>]'
  _pg_user="$1"
  _pg_db="$2"
  _pg_schema="$3"
  _pg_role_prefix="${4:-"$_pg_db"}"

  _pg_owner="${_pg_role_prefix}_owner"
  _pg_reader="${_pg_role_prefix}_reader"
  _pg_writer="${_pg_role_prefix}_writer"

  cat <<-EOSQL
	-- schema
	GRANT USAGE ON SCHEMA $_pg_schema TO $_pg_owner, $_pg_reader, $_pg_writer;
	GRANT CREATE ON SCHEMA $_pg_schema TO $_pg_owner;

	-- existing tables
	GRANT SELECT                                   ON ALL TABLES IN SCHEMA $_pg_schema TO $_pg_reader;
	GRANT SELECT, INSERT, UPDATE, DELETE           ON ALL TABLES IN SCHEMA $_pg_schema TO $_pg_writer;
	GRANT ALL PRIVILEGES                           ON ALL TABLES IN SCHEMA $_pg_schema TO $_pg_owner;

	-- existing sequences
	GRANT SELECT                                   ON ALL SEQUENCES IN SCHEMA $_pg_schema TO $_pg_reader;
	GRANT USAGE                                    ON ALL SEQUENCES IN SCHEMA $_pg_schema TO $_pg_writer, $_pg_owner;

	-- existing functions
	GRANT EXECUTE                                  ON ALL FUNCTIONS IN SCHEMA $_pg_schema TO $_pg_reader, $_pg_writer, $_pg_owner;

	-- default privileges for future objects
	ALTER DEFAULT PRIVILEGES FOR USER $_pg_user IN SCHEMA $_pg_schema GRANT SELECT                         ON TABLES    TO $_pg_reader;
	ALTER DEFAULT PRIVILEGES FOR USER $_pg_user IN SCHEMA $_pg_schema GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO $_pg_writer;
	ALTER DEFAULT PRIVILEGES FOR USER $_pg_user IN SCHEMA $_pg_schema GRANT ALL PRIVILEGES                 ON TABLES    TO $_pg_owner;
	ALTER DEFAULT PRIVILEGES FOR USER $_pg_user IN SCHEMA $_pg_schema GRANT SELECT                         ON SEQUENCES TO $_pg_reader;
	ALTER DEFAULT PRIVILEGES FOR USER $_pg_user IN SCHEMA $_pg_schema GRANT USAGE                          ON SEQUENCES TO $_pg_writer, $_pg_owner;
	ALTER DEFAULT PRIVILEGES FOR USER $_pg_user IN SCHEMA $_pg_schema GRANT EXECUTE                        ON FUNCTIONS TO $_pg_reader, $_pg_writer, $_pg_owner;
EOSQL
}
export pgDbGrantAllOnSchemaSQL
readonly pgDbGrantAllOnSchemaSQL