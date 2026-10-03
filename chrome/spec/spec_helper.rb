# frozen_string_literal: true

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
end

# expect { condition }.to eventually_be_true: retry the block for up to 5 seconds.
RSpec::Matchers.define :eventually_be_true do
  supports_block_expectations
  match do |block|
    deadline = Time.now + 5
    sleep 0.05 until (ok = block.call) || Time.now > deadline
    ok
  end
end
