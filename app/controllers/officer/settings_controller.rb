module Officer
     class SettingsController < BaseController
          def show
               @settings = AppSetting.current
          end

          def update
               @settings = AppSetting.current
               if @settings.update(settings_params)
                    redirect_to officer_settings_path,
                      notice: "Email access setting saved.",
                      status: :see_other
               else
                    render :show, status: :unprocessable_entity
               end
          end

          private

               def settings_params
                    params.require(:app_setting).permit(:require_tamu_email)
               end
     end
end
