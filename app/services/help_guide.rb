# The guides in docs/, shown on the Help page, so there is one copy to keep current.
class HelpGuide
     GUIDES = {
       member: { file: "USER_GUIDE.md", title: "Member guide" },
       officer: { file: "ADMIN_GUIDE.md", title: "Officer guide" }
     }.freeze

  attr_reader :key, :title

  # Officers run the app and also use it as members would, so they get both guides.
  def self.for(user)
       (user.officer? ? %i[ officer member ] : %i[ member ]).map { |key| new(key) }
  end

  def initialize(key)
       @key = key
    @title = GUIDES.fetch(key).fetch(:title)
  end

  def html
       Kramdown::Document.new(markdown, input: "GFM", hard_wrap: false, syntax_highlighter: nil,
         header_offset: 1, auto_id_prefix: "#{key}-").to_html.html_safe
  end

  private

       # The closing contact section and the links between docs only work when reading the repository.
       def markdown
            Rails.root.join("docs", GUIDES.fetch(key).fetch(:file)).read
              .sub(/^## (Questions|Support)\s.*\z/m, "")
              .gsub(/\[([^\]]+)\]\([^)\s]+\.md\)/, '\1')
       end
end
