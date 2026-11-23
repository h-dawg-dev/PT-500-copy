require "spec_helper"
require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe "Vercel container entrypoint" do
     def run_entrypoint(**values)
          Dir.mktmpdir("vercel-entrypoint") do |directory|
               FileUtils.mkdir_p(File.join(directory, "bin"))
               File.write(File.join(directory, "bin/rails"), <<~BASH)
                    #!/bin/bash
                    printf 'migration=%s task=%s\n' "$DATABASE_URL" "$1"
                    exit "${MIGRATION_EXIT:-0}"
               BASH
               FileUtils.chmod(0o755, File.join(directory, "bin/rails"))
               entrypoint = File.join(directory, "entrypoint")
               FileUtils.cp(File.expand_path("../../bin/vercel-entrypoint", __dir__), entrypoint)
               env = {
                    "DATABASE_URL" => "postgresql://db-pooler.example.test/app",
                    "DATABASE_URL_UNPOOLED" => nil,
                    "POSTGRES_URL_NON_POOLING" => nil,
                    "MIGRATION_EXIT" => nil
               }.merge(values.transform_keys(&:to_s))
               Open3.capture3(env, "bash", "-e", "./entrypoint", "bash", "-c",
                    'printf "server=%s\\n" "$DATABASE_URL"', chdir: directory)
          end
     end

     it "uses the direct URL for migrations and preserves pooling for the server" do
          output, _error, status = run_entrypoint(DATABASE_URL_UNPOOLED: "postgresql://direct.example.test/app")
          expect(status).to be_success
          expect(output).to include("migration=postgresql://direct.example.test/app task=db:vercel_migrate")
          expect(output).to include("server=postgresql://db-pooler.example.test/app")
     end

     it "supports the legacy direct connection variable" do
          output, _error, status = run_entrypoint(POSTGRES_URL_NON_POOLING: "postgresql://legacy.example.test/app")
          expect(status).to be_success
          expect(output).to include("migration=postgresql://legacy.example.test/app")
     end

     it "supports an already-direct DATABASE_URL" do
          output, _error, status = run_entrypoint(DATABASE_URL: "postgresql://direct.example.test/app")
          expect(status).to be_success
          expect(output).to include("migration=postgresql://direct.example.test/app")
     end

     it "rejects a pooled-only migration connection before starting the server" do
          output, error, status = run_entrypoint
          expect(status).not_to be_success
          expect(error).to include("require DATABASE_URL_UNPOOLED")
          expect(output).to be_empty
     end

     it "does not start the server when migrations fail" do
          output, _error, status = run_entrypoint(DATABASE_URL_UNPOOLED: "postgresql://direct.example.test/app", MIGRATION_EXIT: "7")
          expect(status.exitstatus).to eq(7)
          expect(output).not_to include("server=")
     end
end
