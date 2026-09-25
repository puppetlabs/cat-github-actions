require "net/http"
require "json"
require "uri"

HOST = ENV.fetch("FORGE_API_HOST", "https://forgeapi.puppet.com")
CLIENT_ID = ENV.fetch("FORGE_CLIENT_ID")
CLIENT_SECRET = ENV.fetch("FORGE_CLIENT_SECRET")
USERNAME = ENV.fetch("FORGE_USERNAME")
PASSWORD = ENV.fetch("FORGE_PASSWORD")

def make_http(uri)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http
end

# Step 1: obtain a forge-web-client scoped token
token_uri = URI("#{HOST}/oauth/token")
token_request = Net::HTTP::Post.new(token_uri)
token_request.set_form_data(
  "grant_type" => "password",
  "username" => USERNAME,
  "password" => PASSWORD,
  "client_id" => CLIENT_ID,
  "client_secret" => CLIENT_SECRET,
)

token_response = make_http(token_uri).request(token_request)
raise "Failed to obtain token: #{token_response.code} #{token_response.body}" unless token_response.code == "200"

token = JSON.parse(token_response.body)["access_token"]
puts "Token obtained successfully"

# Step 2: fetch API keys
keys_uri = URI("#{HOST}/private/keys")
keys_request = Net::HTTP::Get.new(keys_uri)
keys_request["Authorization"] = "Bearer #{token}"

keys_response = make_http(keys_uri).request(keys_request)
raise "Request failed: #{keys_response.code} #{keys_response.body}" unless keys_response.code == "200"

body = JSON.parse(keys_response.body)
keys = body["results"]
  .map { |key| { id: key["id"], expires_at: key["expires_at"], remaining_days: key["remaining_days"] } }
  .select { |key| key[:remaining_days] && key[:remaining_days] < 30 }

puts keys.inspect
