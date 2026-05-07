require "db"
require "athena-contracts/event_dispatcher"

# :nodoc:
module Athena::ORM::Storable; end

require "./collection/*"
require "./exceptions/*"
require "./events/*"
require "./internal/**"
require "./id/*"
require "./mapping/annotations"
require "./mapping/**"
require "./persisters/entity/*"
require "./persisters/collection/*"
require "./platforms/*"
require "./query/*"
require "./schema/*"
require "./sql/parser"
require "./types/*"
require "./utility/*"

require "./annotations"
require "./connection"
require "./default_repository_factory"
require "./entity"
require "./proxy"
require "./entity_manager"
require "./entity_repository"
require "./listeners_invoker"
require "./native_query"
require "./persister_helper"
require "./unit_of_work"

require "./ext/db"

# Convenience alias to make referencing `Athena::ORM` types easier.
alias AORM = Athena::ORM

alias AORMA = Athena::ORM::Annotations

module Athena::ORM
  VERSION = "0.1.0"

  enum LockMode
    None
  end

  enum HydrationMode
    Object
    SimpleObject
  end
end
