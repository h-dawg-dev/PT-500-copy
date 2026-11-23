class CreateQuestionnaireResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :questionnaire_responses do |t|
      # Filled in only when the person was signed in; anonymous submissions leave it empty.
      t.references :user, foreign_key: true
      t.string :email, null: false
      # Snapshot of QuestionnaireController::QUESTIONS at submit time, so old answers stay readable
      # after the questions change.
      t.jsonb :questions, null: false, default: []
      t.jsonb :answers, null: false, default: {}

      t.timestamps
    end

    add_index :questionnaire_responses, :email
  end
end
