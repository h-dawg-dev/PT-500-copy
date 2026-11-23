module Officer
     class CsvTransfersController < BaseController
          before_action :load_terms

          def show
               if params[:retry_import] == "1"
                    flash.now[:alert] = "Your sign-in was refreshed. Choose the export again and click Import events. No events were imported."
               end
          end

          def create
               result = GetinvolvedEventImport.new(file: params[:file], officer: current_user).call
               if result.success?
                    redirect_to officer_csv_transfer_path,
                                notice: "Imported #{result.created_count} events; skipped #{result.skipped_count} existing references. Review points and categories before recording attendance."
               else
                    @import_errors = result.errors
                    render :show, status: :unprocessable_entity
               end
          end

          def export
               report = params[:report].to_s
               return head :not_found unless OfficerCsvExport::REPORTS.include?(report)

               term = selected_term
               send_data "\uFEFF#{OfficerCsvExport.new(report: report, term: term).generate}",
                         filename: "pts-#{report}-#{term ? "term-#{term.id}" : "all-time"}-#{Date.current.iso8601}.csv",
                         type: "text/csv; charset=utf-8", disposition: "attachment"
          end

       private

            def load_terms
                 response.headers["Cache-Control"] = "no-store"
                 @terms = Term.chronological.to_a.reverse
                 @current_term = Term.current
            end

            def selected_term
                 return nil if params[:term_id] == "all"
                 return @current_term if params[:term_id].blank?

                 Term.find(params[:term_id])
            end
     end
end
