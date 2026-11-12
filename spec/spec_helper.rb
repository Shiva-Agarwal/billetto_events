if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start("rails") do
    add_group "Domain", "app/domain"
    add_group "Integrations", "app/integrations"
    add_group "Integrators", "app/integrators"
    add_group "Queries", "app/queries"
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "tmp/rspec_examples.txt"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
