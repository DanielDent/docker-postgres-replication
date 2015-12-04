#!/bin/bash
set -e

# Based on official postgres package's entrypoint script (https://hub.docker.com/_/postgres/)
# Modified to be able to set up a slave. The docker-entrypoint-initdb.d hook provided is inadequate.

set_listen_addresses() {
	sedEscapedValue="$(echo "$1" | sed 's/[\/&]/\\&/g')"
	sed -ri "s/^#?(listen_addresses\s*=\s*)\S+/\1'$sedEscapedValue'/" "$PGDATA/postgresql.conf"
}

if [ "$1" = 'postgres' ]; then
	mkdir -p "$PGDATA"
	chown -R postgres "$PGDATA"

	chmod g+s /run/postgresql
	chown -R postgres /run/postgresql

	# look specifically for PG_VERSION, as it is expected in the DB dir
	if [ ! -s "$PGDATA/PG_VERSION" ]; then
	    if [ "x$REPLICATE_FROM" == "x" ]; then
		    gosu postgres initdb
        else
            until gosu postgres pg_basebackup -h ${REPLICATE_FROM} -D ${PGDATA} -U ${PGUSER} -vP
            do
                echo "Waiting for master to be available..."
                sleep 1s
            done
            chmod 700 ${PGDATA}
        fi

		# check password first so we can output the warning before postgres
		# messes it up
		if [ "$PGPASSWORD" ]; then
			pass="PASSWORD '$PGPASSWORD'"
			authMethod=md5
		else
			# The - option suppresses leading tabs but *not* spaces. :)
			cat >&2 <<-'EOWARN'
				****************************************************
				WARNING: No password has been set for the database.
				         This will allow anyone with access to the
				         Postgres port to access your database. In
				         Docker's default configuration, this is
				         effectively any other container on the same
				         system.

				         Use "-e PGPASSWORD=password" to set
				         it in "docker run".
				****************************************************
			EOWARN

			pass=
			authMethod=trust
		fi

		if [ "x$REPLICATE_FROM" == "x" ]; then

		{ echo; echo "host replication all 0.0.0.0/0 $authMethod"; } >> "$PGDATA/pg_hba.conf"
		{ echo; echo "host all all 0.0.0.0/0 $authMethod"; } >> "$PGDATA/pg_hba.conf"

		# internal start of server in order to allow set-up using psql-client		
		# does not listen on TCP/IP and waits until start finishes
		gosu postgres pg_ctl -D "$PGDATA" \
			-o "-c listen_addresses=''" \
			-w start

		: ${PGUSER:=postgres}
		: ${POSTGRES_DB:=$PGUSER}
		export PGUSER POSTGRES_DB

		if [ "$POSTGRES_DB" != 'postgres' ]; then
			psql --username postgres <<-EOSQL
				CREATE DATABASE "$POSTGRES_DB" ;
			EOSQL
			echo
		fi

		if [ "$PGUSER" = 'postgres' ]; then
			op='ALTER'
		else
			op='CREATE'
		fi

		psql --username postgres <<-EOSQL
			$op USER "$PGUSER" WITH SUPERUSER $pass ;
		EOSQL
		echo

        fi

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)  echo "$0: running $f"; . "$f" ;;
				*.sql) echo "$0: running $f"; psql --username "$PGUSER" --dbname "$POSTGRES_DB" < "$f" && echo ;;
				*)     echo "$0: ignoring $f" ;;
			esac
			echo
		done

        if [ "x$REPLICATE_FROM" == "x" ]; then
		gosu postgres pg_ctl -D "$PGDATA" -m fast -w stop
		fi
		set_listen_addresses '*'

		echo
		echo 'PostgreSQL init process complete; ready for start up.'
		echo
	fi

	exec gosu postgres "$@"
fi

exec "$@"
