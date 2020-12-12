require "./unexpected_result"

class Athena::ORM::Exceptions::NoResult < Athena::ORM::Exceptions::UnexpectedResult
  def initialize
    super "No result was found"
  end
end
