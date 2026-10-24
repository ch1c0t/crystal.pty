# A specialized multi-line formatter for high-concurrency stream tracing
private def debug_log(prefix : String, data : NamedTuple | Hash | String)
  # Prefix every event with its method so concurrent traces are easy to scan.
  method, separator, event = prefix.partition(" :: ")
  indent = "  "

  body = case data
         when String
           data.inspect
         else
           data.map { |k, v| "\n#{indent}#{indent}#{k}: #{v.inspect}" }.join
         end

  method_label = separator.empty? ? "unknown" : method
  event_label = separator.empty? ? prefix : event
  STDERR.puts "\e[36m[PTY DEBUG]\e[0m \e[35m[#{method_label}]\e[0m \e[33m[#{event_label}]\e[0m#{body}\n"
end
