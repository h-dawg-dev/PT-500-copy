module Officer
     class AdministratorsController < BaseController
          def index
               @people = User.order(:last_name, :first_name, :email)
          end

          def update
               person = User.find(params[:id])
               if person.update(role: :officer)
                    redirect_to officer_administrators_path,
                      notice: "#{person.display_name} now has admin access.", status: :see_other
               else
                    redirect_to officer_administrators_path,
                      alert: person.errors.full_messages.to_sentence, status: :see_other
               end
          end
     end
end
