require "test_helper"

class Tcg::EnergyCostTest < ActiveSupport::TestCase
  def payable?(provided, cost)
    Tcg::EnergyCost.payable?(provided, cost)
  end

  test "a colored cost needs Energy of that type" do
    assert payable?(%w[Fire], %w[Fire])
    assert_not payable?(%w[Water], %w[Fire])
    assert_not payable?([], %w[Fire])
  end

  test "Colorless is paid with any Energy" do
    assert payable?(%w[Water], %w[Colorless])
    assert payable?(%w[Water Fire], %w[Colorless Colorless])
    assert_not payable?(%w[Water], %w[Colorless Colorless])
  end

  test "a mixed cost needs the colored part first" do
    assert payable?(%w[Fire Water], %w[Fire Colorless])
    assert payable?(%w[Water Fire], %w[Fire Colorless])
    assert_not payable?(%w[Water Water], %w[Fire Colorless])
  end

  test "each Energy pays for one symbol only" do
    assert_not payable?(%w[Fire], %w[Fire Colorless])
    assert_not payable?(%w[Fire], %w[Fire Fire])
    assert payable?(%w[Fire Fire], %w[Fire Fire])
  end

  test "extra Energy doesn't matter" do
    assert payable?(%w[Fire Fire Fire], %w[Fire])
  end

  test "an attack with no cost can always be used" do
    assert payable?([], [])
    assert payable?(%w[Water], [])
  end
end
