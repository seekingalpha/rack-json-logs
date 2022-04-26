require 'rack-json-logs/version'
require 'rack-json-logs/pretty-printer.rb'
require 'json'
require 'stringio'
require 'socket'

module Rack

  # JsonLogs is a rack middleware that will buffer output, capture exceptions,
  # and log the entire thing as a json object for each request.
  #
  # Options are:
  #
  #   :reraise_exceptions
  #
  #     Whether to re-raise exceptions, or just respond with a standard JSON
  #     500 response.
  #
  #   :from
  #
  #     A string that describes where the request happened. This is useful if,
  #     for example, you want to log which server the request is from. Defaults
  #     to the machine's hostname.
  #
  #   :pretty_print
  #
  #     When set to true, this will pretty-print the logs, instead of printing
  #     the json. This is useful in development.
  #
  #   :print_options
  #
  #     When :pretty_print is set to true, these options will be passed to the
  #     pretty-printer. Run `json-logs-pp -h` to see what the options are.
  #
  #   :file
  #
  #     File path or file object to write log to
  #
  #   :auto_flush
  #
  #     Will flush file to disk on every write
  #
  class JsonLogs

    def initialize(app, options={})
      @app = app
      @options = {
        reraise_exceptions: false,
        pretty_print: false,
        print_options: { trace: true },
        auto_flush: true,
      }.merge(options)
      @options[:from] ||= Socket.gethostname
      @file = @options[:file] || $stdout
      @file = ::File.open(@file, 'a') if @file.is_a?(String)
    end

    def call(env)
      start_time = Time.now
      $stdout, previous_stdout = (stdout_buffer = StringIO.new), $stdout
      $stderr, previous_stderr = (stderr_buffer = StringIO.new), $stderr

      logger = EventLogger.new(start_time)
      env = env.dup; env[:logger] = logger

      begin
        response = @app.call(env)
      rescue Exception => e
        exception = e
      end

      # restore output IOs
      $stderr = previous_stderr; $stdout = previous_stdout

      log = {
        ts: start_time.to_i,
        duration: (Time.now - start_time).round(3),
        request_method: env['REQUEST_METHOD'],
        request: env['PATH_INFO'],
        query_string: env['QUERY_STRING'],
        status: response&.first || 500,
        from: @options[:from],
        pid: Process.pid,
        stdout: stdout_buffer.string,
        stderr: stderr_buffer.string,
      }
      log[:events] =  logger.events if logger.used
      if exception
        log[:exception] = {
          class: exception.class.name,
          message: exception.message,
          backtrace: exception.backtrace,
        }
      end

      if @options[:pretty_print]
        JsonLogs.pretty_print(JSON.parse(log.to_json), @file, @options[:print_options])
      else
        @file.puts(log.to_json)
      end
      @file.flush if @options[:auto_flush]

      raise exception if exception && @options[:reraise_exceptions]

      response || response_500
    end

    def response_500
      [500, { 'Content-Type' => 'application/json' },
       [{ status: 500, message: 'Something went wrong...' }.to_json]]
    end


    # This class can be used to log arbitrary events to the request.
    #
    class EventLogger
      attr_reader :events, :used

      def initialize(start_time)
        @start_time = start_time
        @events     = []
        @used       = false
      end

      # Log an event of type `type` and value `value`.
      #
      def log(type, value)
        @used = true
        @events << {
          type: type,
          value: value,
          time: (Time.now - @start_time).round(3)
        }
      end
    end
  end
end