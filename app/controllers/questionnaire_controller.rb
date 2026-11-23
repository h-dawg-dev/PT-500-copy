class QuestionnaireController < ApplicationController
  include IntakeForm

  # Kept as an alias so existing specs and callers can keep referring to the
  # controller's form definition; the questions live in Questionnaire.
  QUESTIONS = Questionnaire::QUESTIONS

  before_action :require_authentication

  # First-time onboarding only. Once a member has submitted, everything lives
  # together on the "My information" pages.
  def show
    if current_user.questionnaire_completed?
      redirect_to(params[:edit].present? ? edit_profile_path : profile_path)
      return
    end

    @questions = QUESTIONS
    @answers = { "email" => current_user.email }
  end

  def create
    if current_user.questionnaire_completed?
      redirect_to profile_path, alert: "You have already submitted the Member Intake Form."
      return
    end

    save_intake_form(QuestionnaireResponse.new(user: current_user), :show, "Thanks! Your member intake form was received. You can update it here anytime.")
  end

  # Compatibility endpoint for previously opened intake forms, which may not include
  # every current question. Anything such a form did not send stays as it was.
  def update
    submission = current_user.latest_questionnaire_response || QuestionnaireResponse.new(user: current_user)
    submitted = params.fetch(:questionnaire, {})

    answers = current_user.intake_answers.except(*submitted.keys).merge(identity_answers).merge(
      Questionnaire.filter_answers(submitted, questions: Questionnaire.detail_questions)
    )

    if current_user.save_intake(submission, answers)
      redirect_to profile_path, notice: "Your intake answers were updated."
    else
      redirect_to edit_profile_path,
        alert: "Your intake answers could not be saved. #{(submission.errors.full_messages + current_user.errors.full_messages).to_sentence}"
    end
  end

  private

  def identity_answers
    { "name" => current_user.display_name, "email" => current_user.email }.compact
  end
end
