# frozen_string_literal: true

RSpec.describe Duva::Pagination do
  let(:page_class) { Struct.new(:data, :next_cursor) }

  it "follows next_cursor until nil, without ever fetching an extra page" do
    pages = [page_class.new([1, 2], "a"), page_class.new([3], "b"), page_class.new([4, 5], nil)]
    seen_cursors = []

    items = described_class.paginate do |cursor|
      seen_cursors << cursor
      pages[seen_cursors.length - 1]
    end.to_a

    expect(items).to eq([1, 2, 3, 4, 5])
    expect(seen_cursors).to eq([nil, "a", "b"])
  end

  it "a single empty page yields nothing and fetches only once" do
    calls = 0
    items = described_class.paginate do |_cursor|
      calls += 1
      page_class.new([], nil)
    end.to_a

    expect(items).to eq([])
    expect(calls).to eq(1)
  end

  it "max_items stops early without fetching pages it does not need" do
    calls = 0
    items = described_class.paginate(max_items: 2) do |cursor|
      calls += 1
      page_class.new([1, 2, 3], cursor == "used" ? nil : "used")
    end.to_a

    expect(items).to eq([1, 2])
    expect(calls).to eq(1) # the first page's third item is never needed
  end

  it "returns a lazy Enumerator: nothing is fetched before iteration" do
    calls = 0
    enum = described_class.paginate do |_cursor|
      calls += 1
      page_class.new([1], nil)
    end

    expect(calls).to eq(0)
    expect(enum.first).to eq(1)
    expect(calls).to eq(1)
  end
end
