# :nodoc:
class PG::Connection < DB::Connection
  def database_platform : AORM::Platforms::Platform
    AORM::Platforms::Postgres.new
  end

  def last_insert_id : Int64
    self.scalar("SELECT LASTVAL()").as Int64
  end

  def prepare(query : String) : DB::Statement
    visitor = Athena::ORM::SQL::ConvertParameters.new
    Athena::ORM::SQL::Parser.new(false).parse(query, visitor)

    self.build visitor.sql
  end
end
