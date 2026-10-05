require "semantic_version"

# :nodoc:
class MySql::Connection < DB::Connection
  # Detected once per connection, since pooled connections are reused by many entity managers.
  getter database_platform : AORM::Platforms::Platform do
    AORM::Platforms::AbstractMySQL.for_server_version self.scalar("SELECT VERSION()").as(String)
  end

  def last_insert_id : Int64
    self.scalar("SELECT LAST_INSERT_ID()").as Int64
  end

  def prepare(query : String) : DB::Statement
    self.build query
  end
end
