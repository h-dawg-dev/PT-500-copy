module Officer
     class QuestionnaireResponsesController < BaseController
          def index
               response.headers["Cache-Control"] = "no-store"
               @dashboard = QuestionnaireDashboard.new(filters: params.permit(:q, :classification, :email_opt_in, :link_status, :sort))
               @filters = @dashboard.filters
               @page_count = [ (@dashboard.responses.size / 20.0).ceil, 1 ].max
               @page = params[:page].to_i.clamp(1, @page_count)
               @responses = @dashboard.responses.slice((@page - 1) * 20, 20) || []
          end
     end
end
