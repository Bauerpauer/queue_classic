module QC
  class Database

    def initialize(url)
      @db_params = URI.parse(url)
    end

    def execute(sql)
      connection.exec(sql)
    end

    def connection
      if defined? @connection
        @connection
      else
        @connection = PGconn.connect(
          :dbname   => @db_params.path.gsub("/",""),
          :user     => @db_params.user,
          :password => @db_params.password,
          :host     => @db_params.host
        )
        @connection.exec("LISTEN jobs")
        silence_warnings unless ENV["LOGGING_ENABLED"]
        @connection
      end
    end

    def disconnect
      connection.finish
    end

    def init_db
      drop_table
      create_table
      load_functions
    end

    def silence_warnings
      execute("SET client_min_messages TO 'warning'")
    end

    def drop_table
      execute("DROP TABLE IF EXISTS jobs CASCADE")
    end

    def create_table
      execute(
        "CREATE TABLE jobs"    +
        "("                    +
        "id        SERIAL,"    +
        "details   text,"      +
        "locked_at timestamp"  +
        ");"
      )
      execute("CREATE INDEX jobs_id_idx ON jobs (id)")
    end

    def load_functions
      execute(<<-EOD
        CREATE OR REPLACE FUNCTION lock_head() RETURNS SETOF jobs AS $$
        DECLARE
          unlocked integer;
          relative_top integer;
          job_count integer;
          job jobs%rowtype;

        BEGIN
          SELECT TRUNC(random() * 9 + 1) INTO relative_top;
          SELECT count(*) from jobs INTO job_count;

          IF job_count < 10 THEN
            relative_top = 0;
          END IF;

          SELECT id INTO unlocked
            FROM jobs
            WHERE locked_at IS NULL
            ORDER BY id ASC
            LIMIT 1
            OFFSET relative_top
            FOR UPDATE;
          RETURN QUERY UPDATE jobs
            SET locked_at = (CURRENT_TIMESTAMP)
            WHERE id = unlocked AND locked_at IS NULL
            RETURNING *;
        END;
        $$ LANGUAGE plpgsql;
      EOD
      )
    end

  end
end