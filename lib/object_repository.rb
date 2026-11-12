# Resolves any domain object by its TypeID ("event_01j...") without the caller
# having to know which module / table owns it. Models register themselves via
# `has_typeid :prefix` (see HasTypeid) and are referenced in
# config/initializers/object_repository.rb so registration happens on boot/reload.
module ObjectRepository
  NotFound = Class.new(StandardError)
  UnknownType = Class.new(NotFound)

  @registry = Concurrent::Map.new

  class << self
    def register(prefix, klass)
      @registry[prefix.to_s] = klass.name
    end

    def find(tid)
      klass_for(tid).find_by!(tid: tid)
    rescue ActiveRecord::RecordNotFound
      raise NotFound, "no object with tid #{tid.inspect}"
    end

    def exists?(tid)
      klass_for(tid).exists?(tid: tid)
    rescue NotFound, TypeId::InvalidTypeId
      false
    end

    def klass_for(tid)
      prefix, _suffix = TypeId.parse(tid)
      class_name = @registry[prefix] or raise UnknownType, "unknown type id prefix #{prefix.inspect}"
      class_name.constantize
    rescue TypeId::InvalidTypeId => e
      raise NotFound, e.message
    end

    def registered_prefixes = @registry.keys
  end
end
