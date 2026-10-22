# Helper 1: Queries the exit status from the end sentinel or raw process table
private def extract_exit_code(command_transcript : String, end_sentinel : String) : Int32
  if match = command_transcript.match(/#{end_sentinel}__(\d+)__/)
    return match[1].not_nil!.to_i
  end

  if !@reader_active && (proc = @process)
    return proc.wait.exit_code rescue 0
  end

  0
end
