Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :events, only: %i[ index show ] do
    resource :rsvp, only: %i[ create destroy ]
  end

  resource :questionnaire, only: %i[ show create update ], controller: "questionnaire"

  resource :profile, only: %i[ show edit update ]

  get "help" => "help#show"

  # U12.2: a member closing the pop-up that announces officer changes to their points.
  resource :announcement_dismissal, only: :create

  namespace :officer do
    root to: "dashboards#show"
    resources :administrators, only: %i[ index update ]
    resource :settings, only: %i[ show update ]
    resources :terms, only: %i[ index new create edit update ]
    resources :questionnaire_responses, only: :index
    resource :csv_transfer, only: %i[ show create ] do
      get :export
    end
    resources :events do
      resources :attendances, only: %i[ create destroy ]
      resource :attendance_import, only: :create
    end
    # O14.1: member records, each with a point adjustment form. Officer-only, like everything in this namespace (O14.3).
    resources :members, only: %i[ index show ] do
      resources :point_adjustments, only: :create
      resource :dues_payment, only: %i[ create destroy ]
    end
  end

  root "home#show"
end
