namespace :db do
     desc "Apply pending migrations without locking an already-current Vercel database"
     task vercel_migrate: :load_config do
          attempts = 0
          begin
               context = ActiveRecord::Tasks::DatabaseTasks.migration_connection_pool.migration_context
               if context.needs_migration?
                    Rake::Task["db:migrate"].reenable
                    Rake::Task["db:migrate"].invoke
               end
          rescue ActiveRecord::ConcurrentMigrationError
               attempts += 1
               raise if attempts >= 5

               Kernel.warn "Another instance is migrating; checking again in 1s..."
               Kernel.sleep 1
               retry
          end
     end
end
