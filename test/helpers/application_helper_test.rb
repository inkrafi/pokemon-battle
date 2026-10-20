require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "energy_icon names the type" do
    html = energy_icon('Fire')

    assert_includes html, 'data-type="fire"'
    assert_includes html, 'title="Fire"'
    assert_includes html, '<svg'
  end

  test "an unknown type falls back to Colorless" do
    assert_includes energy_icon('Sound'), 'data-type="colorless"'
  end

  test "every card type has a symbol" do
    Card::TYPES.each do |type|
      assert ApplicationHelper::ENERGY_PATHS.key?(type), "no symbol for #{type}"
    end
  end

  test "energy_cost draws one symbol per Energy" do
    html = energy_cost(%w[Fire Colorless Colorless])

    assert_equal 3, html.scan('class="energy ').size
  end

  test "damage_text shows the number and its modifier" do
    assert_equal '60', damage_text('damage' => 60, 'modifier' => nil)
    assert_equal '50+', damage_text('damage' => 50, 'modifier' => '+')
    assert_equal '', damage_text('damage' => nil, 'modifier' => nil)
  end
end
