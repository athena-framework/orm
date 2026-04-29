require "semantic_version"

# :nodoc:
class SQLite3::Connection < DB::Connection
  def database_platform : AORM::Platforms::Platform
    AORM::Platforms::SQLite.new
  end

  def last_insert_id : Int64
    self.scalar("SELECT LAST_INSERT_ROWID()").as Int64
  end

  def prepare(query : String) : DB::Statement
    self.build query
  end
end
