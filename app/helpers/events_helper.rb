module EventsHelper
  def event_price(event)
    return "Free" if event.free?
    return if event.min_price_cents.nil?

    amount = number_with_precision(event.min_price_cents / 100.0, precision: 2, strip_insignificant_zeros: true)
    "From #{amount} #{event.currency}"
  end

  def event_location(event)
    [ event.venue_name, event.city ].compact_blank.uniq.join(", ").presence
  end

  def event_date(event)
    l(event.starts_at, format: "%a %-d %b %Y · %H:%M UTC")
  end

  # Like / dislike control. Clicking your current vote again withdraws it (DELETE).
  def vote_button(item, value)
    label = value == "up" ? "👍 Like" : "👎 Dislike"
    active = item.my_vote == value
    count = value == "up" ? item.upvotes : item.downvotes
    content = safe_join([ label, tag.span(count, class: "vote__count", data: { testid: "#{value}votes-count" }) ], " ")
    css = class_names("vote", "vote--#{value}", "vote--active" => active)
    path = event_vote_path(item.event)

    unless signed_in?
      return link_to(content, sign_in_path(redirect_url: request.fullpath), class: css, title: "Sign in to vote",
        data: { testid: "vote-#{value}" })
    end

    if active
      button_to(content, path, method: :delete, class: css, form: { data: { requires_auth: true } },
        title: "Withdraw your vote", aria: { pressed: true }, data: { testid: "vote-#{value}" })
    else
      button_to(content, path, method: :post, params: { value: value }, class: css, form: { data: { requires_auth: true } },
        aria: { pressed: false }, data: { testid: "vote-#{value}" })
    end
  end
end
