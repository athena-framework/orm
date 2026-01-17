require "semantic_version"

# :nodoc:
abstract class DB::Connection
  def database_platform : AORM::Platforms::Platform
    raise NotImplementedError.new "#{self.class} is not yet supported."
  end

  def prepare(query : String) : DB::Statement
    self.build query
  end
end

# :nodoc:
class DB::Database
  getter database_platform : AORM::Platforms::Platform do
    # Use an actual connection to the underlying DB to determine self's platform.
    self.using_connection do |conn|
      conn.database_platform
    end
  end
end

# PG Extensions

# :nodoc:
class PG::Connection
  def database_platform : AORM::Platforms::Platform
    case self.version
    when .>=(SemanticVersion.new 10, 0, 0)
      AORM::Platforms::Postgres100.new
    when .>=(SemanticVersion.new 9, 4, 0)
      AORM::Platforms::Postgres94.new
    else
      # Otherwise return default version.
      AORM::Platforms::Postgres.new
    end
  end

  def last_insert_id : Int64
    self.scalar("SELECT LASTVAL()").as Int64
  end

  def prepare(query : String) : DB::Statement
    visitor = Athena::ORM::SQL::ConvertParameters.new
    Athena::ORM::SQL::Parser.new(false).parse(query, visitor)

    self.build visitor.sql
  end

  private def version : SemanticVersion
    version = @connection.server_parameters["server_version"]

    parts = version.split('.')

    SemanticVersion.new parts[0].to_i, parts[1].to_i, parts.fetch(2, 0).to_i
  end
end
