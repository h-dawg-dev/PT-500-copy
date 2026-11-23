require "spec_helper"
require "rake"
require "active_record"

RSpec.describe "db:vercel_migrate" do
     around do |example|
          previous_application = Rake.application
          Rake.application = Rake::Application.new
          Rake::Task.define_task("db:load_config")
          Rake::Task.define_task("db:migrate")
          load File.expand_path("../../lib/tasks/vercel.rake", __dir__)
          example.run
     ensure
          Rake.application = previous_application
     end

     let(:context) { instance_double(ActiveRecord::MigrationContext) }
     let(:pool) { double("migration pool", migration_context: context) }
     let(:migration) { Rake::Task["db:migrate"] }
     let(:task) { Rake::Task["db:vercel_migrate"] }

     before do
          allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:migration_connection_pool).and_return(pool)
          allow(context).to receive(:needs_migration?).and_return(true)
          allow(Kernel).to receive(:sleep)
          allow(Kernel).to receive(:warn)
     end

     it "does not acquire a migration lock when the schema is current" do
          allow(context).to receive(:needs_migration?).and_return(false)
          expect(migration).not_to receive(:invoke)
          task.invoke
     end

     it "applies pending migrations with the normal Rails migration task" do
          expect(migration).to receive(:invoke).once
          task.invoke
     end

     it "rechecks the schema after another instance wins the migration lock" do
          allow(context).to receive(:needs_migration?).and_return(true, false)
          expect(migration).to receive(:invoke).once.and_raise(ActiveRecord::ConcurrentMigrationError)
          expect(Kernel).to receive(:sleep).with(1).once
          task.invoke
     end

     it "retries an actual migration when the lock becomes available" do
          calls = 0
          migration.enhance do
               calls += 1
               raise ActiveRecord::ConcurrentMigrationError if calls == 1
          end
          task.invoke
          expect(calls).to eq(2)
     end

     it "fails startup after bounded lock contention" do
          allow(migration).to receive(:invoke).and_raise(ActiveRecord::ConcurrentMigrationError)
          expect(Kernel).to receive(:sleep).with(1).exactly(4).times
          expect { task.invoke }.to raise_error(ActiveRecord::ConcurrentMigrationError)
     end

     it "fails immediately for migration errors other than lock contention" do
          allow(migration).to receive(:invoke).and_raise(StandardError, "migration failed")
          expect(Kernel).not_to receive(:sleep)
          expect { task.invoke }.to raise_error(StandardError, "migration failed")
     end
end
