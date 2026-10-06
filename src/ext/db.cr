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

# Checked once every file has been required, so a driver is detected whether it's required before or after `athena-orm`.
macro finished
  {% if @top_level.has_constant?("PG") %}
    require "./pg"
  {% end %}

  {% if @top_level.has_constant?("MySql") %}
    require "./mysql"
  {% end %}

  {% if @top_level.has_constant?("SQLite3") %}
    require "./sqlite3"
  {% end %}
end
