# frozen_string_literal: true

module Duva
  # Cursor pagination, shared by `events.list_all` and `suppressions.list_all`: follows
  # `next_cursor` until it is `nil`, without ever loading every page into memory at once.
  #
  # @api private
  module Pagination
    # `fetch_page` is called with the current cursor (`nil` for the first page) and must return
    # an object responding to `#data` (an Array) and `#next_cursor`. Returns a lazy Enumerator:
    # nothing is fetched until the caller actually iterates (`each`, `first`, `to_a`...).
    def self.paginate(max_items: nil, &fetch_page)
      Enumerator.new do |yielder|
        cursor = nil
        yielded = 0
        catch(:duva_pagination_done) do
          loop do
            page = fetch_page.call(cursor)
            page.data.each do |item|
              yielder << item
              yielded += 1
              throw :duva_pagination_done if max_items && yielded >= max_items
            end
            break if page.next_cursor.nil?

            cursor = page.next_cursor
          end
        end
      end
    end
  end
end
