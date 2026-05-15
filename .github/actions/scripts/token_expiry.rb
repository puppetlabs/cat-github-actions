require "net/http"
require "json"
require "uri"

HOST = "https://<your-host>"
TOKEN = "<your-token>"

uri = URI("#{HOST}/private/keys")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Get.new(uri)
request["Authorization"] = "Bearer #{TOKEN}"

response = http.request(request)
raise "Request failed: #{response.code}" unless response.code == "200"

body = JSON.parse(response.body)
keys = body["results"].map { |key| { id: key["id"], expires_at: key["expires_at"], remaining_days: key["remaining_days"] } }

puts keys.inspect
