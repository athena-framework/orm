module Athena::ORM::Mapping
  # Type-erased value union for everything the ORM stores in a `Mapping::Value`.
  # Covers `DB::Any` scalars (incl. `Bytes` and `Nil`) plus any `Athena::ORM::Storable` reference (entities, proxies, collections — see `src/athena-orm.cr` for the marker module).
  alias ValueAny = ::DB::Any | Athena::ORM::Storable

  abstract struct Value
    abstract def value : ValueAny
  end

  record SingleValue < Value, value : ValueAny

  record ColumnValue < Value, name : String, value : ValueAny do
    def to_s(io : IO) : Nil
      @value.to_s io
    end

    def inspect(io : IO) : Nil
      @value.inspect io
    end
  end
end
