# Reference terms are also needed after db:schema:load, which skips migration inserts.
# Repeating seeds preserves administrators' edits. Members come from Clerk sign-in.
[
  [ "Spring 2026", Date.new(2026, 1, 13), Date.new(2026, 5, 8) ],
  [ "Fall 2026", Date.new(2026, 8, 17), Date.new(2026, 12, 18) ],
  [ "Spring 2027", Date.new(2027, 1, 12), Date.new(2027, 5, 14) ]
].each do |name, starts_on, ends_on|
  Term.find_or_create_by!(name: name) do |term|
    term.assign_attributes(starts_on: starts_on, ends_on: ends_on,
      required_points: 7, required_professional_points: 1, required_social_points: 1)
  end
end
