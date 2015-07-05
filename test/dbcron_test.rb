require "test_helper"

class TestDBcron < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::DBcron::VERSION
  end
end
