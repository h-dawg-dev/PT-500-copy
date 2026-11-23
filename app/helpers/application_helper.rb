module ApplicationHelper
  def clinic_clock(time)
    return if time.blank?

    time.in_time_zone.strftime("%a %b %d · %I:%M %p")
  end

  def clinic_hour(time)
    return if time.blank?

    time.in_time_zone.strftime("%I:%M %p")
  end

  def signed_points(points)
    format("%+d", points)
  end

  # "Added 2 professional points" or "Subtracted 1 general point".
  def point_change(adjustment)
    amount = pluralize(adjustment.points.abs, "#{adjustment.category} point")
    adjustment.points.positive? ? "Added #{amount}" : "Subtracted #{amount}"
  end

  def session_path_for(event)
    current_user&.officer? ? officer_event_path(event) : event_path(event)
  end

  def datetime_local_value(time)
    time&.in_time_zone&.strftime("%Y-%m-%dT%H:%M")
  end

  def highlight_query(text, query)
    highlight(text.to_s, query.to_s.split(/\s+/).reject(&:blank?))
  end

  # The stored label for a choice answer, from the question snapshot saved
  # with the response. Falls back to the raw value for old or free-form rows.
  def questionnaire_answer_label(response, key)
    question = Array(response.questions).find { |entry| entry["key"].to_s == key.to_s }
    value = response.answers[key.to_s]
    return "Not answered" if value.blank?

    question&.dig("options", value).presence || value.to_s
  end

# U30.1: the customer-approved FlyWire destination, set in DUES_PAYMENT_URL.
# Only https addresses are used, and the link is hidden if none is set.
def dues_payment_url
  url = ENV["DUES_PAYMENT_URL"].to_s.strip
  url if url.start_with?("https://")
end
end
