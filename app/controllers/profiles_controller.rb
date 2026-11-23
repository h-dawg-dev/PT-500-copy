class ProfilesController < ApplicationController
  include IntakeForm

  before_action :require_authentication
  before_action :set_user
  before_action :require_submitted_form, only: %i[ edit update ]
  before_action :set_intake_form, only: %i[ edit update ]

  # Follows the current form, so a question added after someone submitted shows as unanswered.
  def show
    return unless @user.questionnaire_completed?

    answers = @user.intake_answers
    @intake_rows = Questionnaire::QUESTIONS.map do |question|
      value = answers[question[:key].to_s]
      [ question[:prompt], question.fetch(:options, {}).fetch(value, value) ]
    end
  end

  def edit
  end

  def update
    save_intake_form(@user.latest_questionnaire_response, :edit, "Your information was updated.")
  end

  private

  # Always the signed-in member. There is no id in the route, so nobody else's record is reachable.
  def set_user
    @user = current_user
  end

  def require_submitted_form
    redirect_to questionnaire_path unless @user.questionnaire_completed?
  end

  # The saved values stay as they are when a rejected form comes back, so the page
  # can still tell what has not been saved.
  def set_intake_form
    @questions = Questionnaire::QUESTIONS
    @answers = @user.intake_answers
    @saved_information = Questionnaire.field_values(@answers)
  end
end
