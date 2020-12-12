abstract struct Athena::ORM::Platforms::Keywords::List
  private getter keyword_set : Set(String) { Set.new self.keywords.map &.upcase }

  abstract def name : String

  protected abstract def keywords : Indexable(String)

  def keyword?(keyword : String) : Bool
    self.keyword_set.includes? keyword
  end
end
