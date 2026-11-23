require "rails_helper"

RSpec.describe PreferLocalhost do
  let(:app) { ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] } }
  let(:middleware) { described_class.new(app) }

  it "sends the loopback IP to localhost and drops the Clerk handshake" do
    env = Rack::MockRequest.env_for("http://127.0.0.1:3000/?__clerk_handshake=secret&__clerk_db_jwt=secret&next=home")

    status, headers, = middleware.call(env)

    expect(status).to eq(302)
    location = headers["location"]
    expect(location).to start_with("http://localhost:3000/")
    expect(location).to include("next=home")
    expect(location).not_to include("__clerk")
    expect(location).not_to include("secret")
  end

  it "leaves localhost requests alone" do
    status, = middleware.call(Rack::MockRequest.env_for("http://localhost:3000/"))

    expect(status).to eq(200)
  end
end
