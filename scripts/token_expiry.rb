require "net/http"
require "json"
require "uri"

HOST = "https://forgeapi.puppet.com"
TOKEN = ENV.fetch("API_KEY")

uri = URI("#{HOST}/private/keys")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Get.new(uri)
request["Authorization"] = "Bearer #{TOKEN}"
puts "Using token: #{TOKEN[0..5]}..."

response = http.request(request)
puts response["location"]
puts response.code
puts response.body
raise "Request failed: #{response.code}" unless response.code == "200"

puts response["location"]

body = JSON.parse(response.body)
keys = body["results"].map { |key| { id: key["id"], expires_at: key["expires_at"], remaining_days: key["remaining_days"] } }

puts keys.inspect
