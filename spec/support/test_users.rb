module TestUsers
  def create_user(attrs = {})
    token = SecureRandom.hex(4)
    User.create!({
      clerk_user_id: "user_#{token}",
      email: "user_#{token}@example.com",
      first_name: "Iris",
      last_name: "Klingbeil",
      role: :member
    }.merge(attrs))
  end

  def create_officer(attrs = {})
    create_user({
      first_name: "Hudson",
      last_name: "Lee",
      role: :officer
    }.merge(attrs))
  end

  def create_term(attrs = {})
    Term.create!({
      name: "Term #{SecureRandom.hex(3)}",
      starts_on: Date.new(2026, 8, 17),
      ends_on: Date.new(2026, 12, 18),
      required_points: 7,
      required_professional_points: 1,
      required_social_points: 1
    }.merge(attrs))
  end

  def create_current_term
    Term.current || create_term(starts_on: Date.current - 45.days, ends_on: Date.current + 45.days)
  end
end
