# Lazy ToOne wrapper for owning-side associations.
#
# Users opt into lazy loading by typing a ToOne field as `Proxy(Target)?`.
# A plain `Target?` keeps the existing eager-deferred behavior.
#
# Raw entity assignment (`user.avatar = some_avatar`) therefore requires
# an explicit wrap: `user.avatar = AORM::Proxy(Avatar).wrap(some_avatar)`.
#
# Reads through the proxy go via `forward_missing_to inner` and trigger a load on first access.
# Code that needs the raw `Target` reference (to pass to a function whose signature expects it, or to do an `is_a?` check against a subclass) calls `.inner` explicitly.
#
# Object identity is NOT preserved across a load: once the proxy loads, the loaded `Target` registers in the identity map and replaces the proxy as the canonical record.
# Stale proxy references stay functional via `@inner`.
#
# Owning-side ToOne only.
# Inverse-side OneToOne stays eager via `BasicEntityPersister#load_one_to_one_entity`; the annotation driver rejects `Proxy(T)?` typing on inverse-side fields.
class Athena::ORM::Proxy(T) < Athena::ORM::Entity
  def self.create_class_metadata(driver : Athena::ORM::Mapping::Driver::Annotation) : Athena::ORM::Mapping::ClassInterface
    raise "BUG: Proxy(#{T}) reached the metadata factory; lookups for proxies must pass `target_class` (=#{T}) instead of `entity.class`"
  end

  @em : Athena::ORM::EntityManagerInterface?
  @id : Hash(String, ::DB::Any)?

  # On first call: removes self from the identity map,  loads the target via the persister (which re-registers under the same `(T, id_hash)` slot), caches the result on `@inner`, and returns it.
  # Subsequent calls return the cached value directly.
  getter inner : T do
    em = @em || raise "Proxy(#{T}) is unbound; construct via `Proxy.wrap` if you have a loaded entity, or use `EntityManager#find` instead"
    id = @id || raise "Proxy(#{T}) has no identifier"

    uow = em.unit_of_work
    # Vacate this proxy's identity-map slot before loading so the persister's `register_managed` of the loaded entity doesn't trip the collision check.
    # The guard handles proxies built via `from_id` without going through the UoW (e.g. unit tests).
    uow.remove_from_identity_map self if uow.is_in_identity_map self

    loaded = uow.entity_persister(T).load(id)
    raise "Proxy target #{T} with id #{id.inspect} not found" if loaded.nil?

    loaded.as(T)
  end

  forward_missing_to inner

  protected def initialize(@em : Athena::ORM::EntityManagerInterface, @id : Hash(String, ::DB::Any))
  end

  protected def initialize(@inner : T)
  end

  # Wraps an already-loaded entity.
  # The resulting proxy is `loaded?` from the start and never issues a SELECT.
  def self.wrap(value : T) : self
    new value
  end

  # Idempotent: passing through an existing proxy returns it unchanged.
  def self.wrap(value : Proxy(T)) : Proxy(T)
    value
  end

  # Constructs an unloaded proxy bound to *em* and the target's identifier hash.
  # The first `inner` call loads the proxy via `em.unit_of_work.entity_persister(T).load(id)` and replaces this proxy in the identity map with the loaded entity.
  def self.from_id(em : Athena::ORM::EntityManagerInterface, id : Hash(String, ::DB::Any)) : self
    new em, id
  end

  # The wrapped target class.
  def target_class : Athena::ORM::Entity.class
    T
  end

  # Identifier hash carried by an un-loaded proxy, or nil for proxies built via `wrap`.
  def proxy_id : Hash(String, ::DB::Any)?
    @id
  end

  def loaded? : Bool
    !@inner.nil?
  end

  # Non-loading accessor: returns the inner if present, nil otherwise.
  # Used internally during commit to inspect proxies without forcing a SELECT.
  def inner? : T?
    @inner
  end

  def inspect(io : IO) : Nil
    io << "AORM::Proxy(" << T << ", loaded=" << self.loaded? << ')'
  end

  # Allows reading the `#id` of a proxy without triggering a load.
  #
  # Hardcoded to the method name `id` and the field key `"id"` since that's the standard PK name.
  # Composite PKs and entities whose PK ivar isn't named `id` still trigger a load through `forward_missing_to inner` if calling `proxy.<some_other_pk>`.
  def id
    {% begin %}
      {% pk_ivar = T.instance_vars.find { |iv| iv.annotation(::Athena::ORM::Annotations::ID) && iv.name.stringify == "id" } %}
      {% if pk_ivar %}
        {% non_nil_type = pk_ivar.type.nilable? ? pk_ivar.type.union_types.reject(&.nilable?).first : pk_ivar.type %}
        if inner = @inner
          inner.id
        else
          @id.not_nil!["id"].not_nil!.as({{non_nil_type}})
        end
      {% else %}
        raise "Proxy(#{T}) has no field named `id` tagged with @[AORMA::ID]; use `.proxy_id` for the raw identifier hash or `.inner.<your_pk>` to load and read the actual PK value."
      {% end %}
    {% end %}
  end
end
