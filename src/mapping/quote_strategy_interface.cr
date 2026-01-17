module Athena::ORM::Mapping::QuoteStrategyInterface
  def sql_result_casing(platform : Platforms::Platform, column : String) : String
    if platform.is_a? Platforms::Postgres
      return column.downcase
    end

    column
  end
end
