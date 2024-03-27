
# TODO: write actual unit tests :).

$: << File.expand_path('../lib/', __FILE__)
require 'rack-json-logs'

use Rack::JsonLogs, pretty_print: true

run ->(env) do
  puts "hello world"
  env[:logger].log(:event, 'something awesome happened')
  $stderr.puts "bye world"
  raise "exception on purpose"
  [200, {'content-type' => 'text/html'}, ['Hello Rack!']]
end
