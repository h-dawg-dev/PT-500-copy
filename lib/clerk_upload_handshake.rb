require "uri"

# Clerk's 307 would replay a multipart upload to its browser-only handshake endpoint.
class ClerkUploadHandshake
     def initialize(app)
          @app = app
     end

     def call(env)
          rewrite_handshake(env, @app.call(env))
     end

  private

       def rewrite_handshake(env, response)
            status, headers, body = response
            return response unless status == 307 && env["REQUEST_METHOD"] == "POST" && env["PATH_INFO"] == "/officer/csv_transfer"

            key = headers.key?("location") ? "location" : "Location"
            destination = URI.parse(headers[key].to_s)
            return response unless destination.scheme == "https" && destination.path == "/v1/client/handshake"

            # After authentication, return to the upload page with an explicit retry message.
            query = URI.decode_www_form(destination.query.to_s).map do |name, value|
                 if name == "redirect_url"
                      retry_url = URI.parse(value)
                      retry_query = URI.decode_www_form(retry_url.query.to_s).reject { |item| item.first == "retry_import" }
                      retry_url.query = URI.encode_www_form(retry_query + [ [ "retry_import", "1" ] ])
                      value = retry_url.to_s
                 end
                 [ name, value ]
            end
            destination.query = URI.encode_www_form(query)
            [ 303, headers.merge(key => destination.to_s), body ]
          rescue URI::InvalidURIError, ArgumentError
               response
     end
end
