# Gives an ActiveRecord model a public, immutable, time-ordered TypeID column (`tid`)
# and registers it in the ObjectRepository.
#
#   class Catalog::Event < ApplicationRecord
#     has_typeid :event
#   end
module HasTypeid
  extend ActiveSupport::Concern

  class_methods do
    def has_typeid(prefix)
      class_attribute :typeid_prefix, instance_writer: false, default: prefix.to_s
      ObjectRepository.register(prefix, self)

      attr_readonly :tid
      after_initialize { self.tid ||= TypeId.generate(typeid_prefix) if new_record? }
      validates :tid, presence: true
    end
  end

  def to_param = tid
end
