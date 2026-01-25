require "./unexpected_result"

class Athena::ORM::Exceptions::NonUniqueResult < Athena::ORM::Exceptions::UnexpectedResult
  def initialize
    super "More than one result was found"
  end
end
