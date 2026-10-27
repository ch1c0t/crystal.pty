# Separates lifecycle summaries from high-volume PTY internals.
DEBUG_LOG = ::Log.for("pty.session")
TRACE_LOG = ::Log.for("pty.session.trace")

# Lifecycle events are DEBUG; output and synchronization details are TRACE.
private def debug_log(prefix : String, data : NamedTuple | Hash | String)
  method, separator, event = prefix.partition(" :: ")
  method_label = separator.empty? ? "unknown" : method
  event_label = separator.empty? ? prefix : event

  if method_label == "start" &&
     (event_label == "Boot Sequence Triggered" || event_label == "Already Running")
    DEBUG_LOG.debug { formatted_debug_log(method_label, event_label, data) }
  else
    TRACE_LOG.trace { formatted_debug_log(method_label, event_label, data) }
  end
end

private def formatted_debug_log(method_label : String, event_label : String, data : NamedTuple | Hash | String) : String
  indent = "  "
  body = case data
         when String
           data.inspect
         else
           data.map { |k, v| "\n#{indent}#{indent}#{k}: #{v.inspect}" }.join
         end

  "#{method_label} :: #{event_label}#{body}"
end
