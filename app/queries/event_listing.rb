# Read side for the events page: upcoming events + vote counts + the viewer's own votes,
# in 2 queries per page regardless of page size (no N+1).
#
# Uses keyset pagination on (starts_at, id) - backed by a composite index - instead of
# OFFSET, so page 1000 costs the same as page 1 and pages don't shift when events are added.
class EventListing
  PER_PAGE = 24

  Item = Data.define(:event, :upvotes, :downvotes, :my_vote) do
    def score = upvotes - downvotes
  end
  Page = Data.define(:items, :next_cursor)

  def initialize(viewer_id: nil, now: Time.current)
    @viewer_id = viewer_id
    @now = now
  end

  def page(after: nil, per: PER_PAGE)
    rows = scope(decode_cursor(after)).limit(per + 1).to_a
    has_more = rows.size > per
    rows = rows.first(per)
    my_votes = votes_of_viewer(rows.map(&:tid))

    items = rows.map do |event|
      Item.new(event: event, upvotes: event.upvotes.to_i, downvotes: event.downvotes.to_i, my_vote: my_votes[event.tid])
    end
    Page.new(items: items, next_cursor: has_more ? encode_cursor(rows.last) : nil)
  end

  private

  def scope(cursor)
    relation = Catalog::Event.upcoming(@now).chronological
      .joins("LEFT JOIN event_vote_tallies ON event_vote_tallies.event_tid = catalog_events.tid")
      .select("catalog_events.*",
        "COALESCE(event_vote_tallies.upvotes, 0) AS upvotes",
        "COALESCE(event_vote_tallies.downvotes, 0) AS downvotes")
    return relation unless cursor

    relation.where("(catalog_events.starts_at, catalog_events.id) > (?, ?)", *cursor)
  end

  def votes_of_viewer(event_tids)
    return {} if @viewer_id.blank? || event_tids.empty?

    Voting::Vote.active.where(user_id: @viewer_id, event_tid: event_tids).pluck(:event_tid, :value).to_h
  end

  def encode_cursor(event)
    Base64.urlsafe_encode64("#{event.starts_at.utc.iso8601(6)}|#{event.id}", padding: false)
  end

  def decode_cursor(cursor)
    return if cursor.blank?

    starts_at, id = Base64.urlsafe_decode64(cursor).split("|", 2)
    [ Time.iso8601(starts_at), Integer(id) ]
  rescue ArgumentError
    nil
  end
end
