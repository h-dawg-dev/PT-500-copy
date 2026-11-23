require "rails_helper"
require "clerk/authenticate_context"
require "clerk/authenticate_request"
require "base64"

RSpec.describe ClerkUploadHandshake do
     let(:configuration) do
          Clerk::Configuration.new.tap do |config|
               config.update(secret_key: "sk_test_dummy", publishable_key: "pk_test_#{Base64.strict_encode64('auth.example.test$')}")
          end
     end
     let(:authentication) do
          lambda do |env|
               context = Clerk::AuthenticateContext.new(Rack::Request.new(env), configuration)
               Clerk::AuthenticateRequest.new(context).resolve(env)
          end
     end
     let(:env) do
          Rack::MockRequest.env_for("https://pts.example.test/officer/csv_transfer", method: "POST",
                                   "HTTP_ACCEPT" => "text/html", "HTTP_SEC_FETCH_DEST" => "document", input: "uploaded file bytes")
     end

     it "uses GET for the real SDK's handshake rather than replaying the upload POST" do
          original = authentication.call(env)
          expect(original.first).to eq(307)
          expect(URI.parse(original[1]["location"]).path).to eq("/v1/client/handshake")
          status, headers, = described_class.new(authentication).call(env)
          expect(status).to eq(303)
          destination = URI.parse(headers["location"])
          expect(destination.host).to eq("auth.example.test")
          retry_url = URI.parse(URI.decode_www_form(destination.query).to_h.fetch("redirect_url"))
          expect(retry_url.path).to eq("/officer/csv_transfer")
          expect(URI.decode_www_form(retry_url.query).to_h).to include("retry_import" => "1")
     end

     it "preserves GET handshakes and redirects for other POST endpoints" do
          [ [ "GET", "/officer/csv_transfer" ], [ "POST", "/officer/events" ] ].each do |method, path|
               request = Rack::MockRequest.env_for("https://pts.example.test#{path}", method: method, "HTTP_ACCEPT" => "text/html")
               expect(described_class.new(authentication).call(request).first).to eq(307)
          end
     end

     it "does not swallow errors from the application" do
          app = ->(_) { raise ArgumentError, "application failure" }
          expect { described_class.new(app).call(env) }.to raise_error(ArgumentError, "application failure")
     end

     it "preserves ordinary success, login and application redirects" do
          [ [ 200, {}, [ "ok" ] ], [ 302, { "location" => "/sign-in" }, [] ],
            [ 307, { "location" => "https://pts.example.test/other" }, [] ] ].each do |response|
               app = ->(_) { response }
               expect(described_class.new(app).call(env)).to eq(response)
          end
     end
end
