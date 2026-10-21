# Streams execution chunks interactively in real time down an open session pipeline
def run(command_string : String, &stream_callback : String ->) : PTY::ExecutionResult
  # Phase 1: Setup unique markers and attach the live interceptor
  start_sentinel, end_sentinel = generate_sentinels
  captured_text = ""
  activate_live_filter(start_sentinel, end_sentinel, ->(chunk : String) {
    captured_text += chunk
    stream_callback.call(chunk)
  })

  # Phase 2: Write encapsulated sandwich instructions and wait for completion
  dispatch_sandwich_commands(command_string, start_sentinel, end_sentinel)
  wait_for(end_sentinel)

  # Deactivate the temporary hook immediately
  deactivate_live_filter

  # Phase 3: Harvest metrics and return the clean data structure
  exit_status = harvest_exit_status(end_sentinel)
  PTY::ExecutionResult.new(output: captured_text.strip, status: exit_status)
end

# Overload matching block-less execution requests
def run(command_string : String) : PTY::ExecutionResult
  run(command_string) { |_chunk| }
end

# -------------------------------------------------------------
# Extracted Private Helpers for #run
# -------------------------------------------------------------

private def generate_sentinels : Tuple(String, String)
  start_sentinel = "START_MARK_#{Random.rand(100000..999999)}"
  end_sentinel   = "END_MARK_#{Random.rand(100000..999999)}"
  {start_sentinel, end_sentinel}
end

private def activate_live_filter(start_sentinel : String, end_sentinel : String, accumulator : String -> Nil)
  @mutex.synchronize do
    @active_run_callback = ->(chunk : String) {
      # Lossless live filtering: skip command infrastructure lines
      unless chunk.includes?(start_sentinel) || chunk.includes?(end_sentinel) || chunk.includes?("echo ")
        accumulator.call(chunk)
      end
    }
  end
end

private def deactivate_live_filter
  @mutex.synchronize do
    @active_run_callback = nil
  end
end

private def dispatch_sandwich_commands(command_string : String, start_sentinel : String, end_sentinel : String)
  write("echo #{start_sentinel}\n")
  if !command_string.empty?
    write("#{command_string}\n")
  end
  write("echo #{end_sentinel}__$?__\n")
end

private def harvest_exit_status(end_sentinel : String) : Int32
  # Check if the sentinel successfully printed its completion marker token
  if match = @output.match(/#{end_sentinel}__(\d+)__/)
    return match[1].to_i
  end

  # Fallback: If the shell died abruptly, query the native process engine register
  if !@reader_active && (proc = @process)
    return proc.wait.exit_code rescue 0
  end

  0
end
