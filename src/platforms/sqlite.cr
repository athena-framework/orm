# Base platform for SQLite.
class Athena::ORM::Platforms::SQLite < Athena::ORM::Platforms::Platform
  protected def do_modify_limit_query(sql : String, limit : Int?, offset : Int) : String
    if limit.nil? && offset > 0
      limit = -1
    end

    super query, limit, offset
  end
end
