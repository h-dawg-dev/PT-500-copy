module Officer
     class TermsController < BaseController
          before_action :set_term, only: %i[edit update]

          def index
               @terms = Term.chronological.reverse
               @current_term = Term.current
          end

          def new
               @term = Term.new(
                 starts_on: Date.current,
                 ends_on: Date.current + 4.months,
                 required_points: User::REQUIRED_POINTS,
                 required_professional_points: User::REQUIRED_CATEGORY_POINTS.fetch("professional"),
                 required_social_points: User::REQUIRED_CATEGORY_POINTS.fetch("social")
               )
          end

          def create
               @term = Term.new(term_params)
               if @term.save
                    redirect_to officer_terms_path,
                      notice: "#{@term.name} was created and events in its date range were assigned.",
                      status: :see_other
               else
                    render :new, status: :unprocessable_entity
               end
          end

          def edit
          end

          def update
               if @term.update(term_params)
                    redirect_to officer_terms_path,
                      notice: "#{@term.name} was updated and its events were reassigned.",
                      status: :see_other
               else
                    render :edit, status: :unprocessable_entity
               end
          end

          private

               def set_term
                    @term = Term.find(params[:id])
               end

               def term_params
                    params.require(:term).permit(
                      :name,
                      :starts_on,
                      :ends_on,
                      :required_points,
                      :required_professional_points,
                      :required_social_points
                    )
               end
     end
end
