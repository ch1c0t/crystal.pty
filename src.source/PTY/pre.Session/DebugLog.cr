# A specialized multi-line formatter for high-concurrency stream tracing
private def debug_log(prefix : String, data : NamedTuple | Hash | String)
  # Standardize layout into clean indents
  indent = "  "
  
  # Format the key/value payload cleanly
  body = case data
         when String
           data.inspect
         else
           # Map NamedTuple or Hash keys line-by-line with deep indents
           data.map { |k, v| "\n#{indent}#{indent}#{k}: #{v.inspect}" }.join
         end

  # Output to standard error so it never collides with standard output wires
  STDERR.puts "\e[36m[PTY DEBUG]\e[0m \e[33m#{prefix}\e[0m#{body}\n"
end
