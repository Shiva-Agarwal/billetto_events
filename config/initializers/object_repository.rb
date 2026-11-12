# Reference every domain object that `has_typeid` so it registers its TypeID prefix in the
# ObjectRepository on boot (and again after each code reload in development).
Rails.configuration.to_prepare do
  Catalog::Event
end
