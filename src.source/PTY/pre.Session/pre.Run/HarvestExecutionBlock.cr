private def harvest_execution_block(
  snapshot_index : Int32, 
  command_string : String, 
  start_sentinel : String, 
  end_sentinel : String, 
  captured_text : String
) : PTY::ExecutionResult

  command_transcript = @output[snapshot_index..-1]
  exit_status = 0
  clean_output = ""

  # Allow leading prompts before the start sentinel here as well
  if match = command_transcript.match(/START_MARK_\d+_\d+\r?\n([\s\S]*?)#{end_sentinel}__(\d+)__/)
    exit_status = match[2].to_i
    # Grab index 1 to isolate ONLY the inner execution content payload block
    clean_output = match[1].gsub(/#{command_string}\r?\n/, "").strip
  else
    if !@reader_active && (proc = @process)
      exit_status = proc.wait.exit_code rescue 0
    end
    clean_output = captured_text
      .gsub(/#{command_string}\r?\n/, "")
      .gsub(/echo #{start_sentinel}\r?\n/, "")
      .gsub(/echo #{end_sentinel}__\$\?__\r?\n/, "")
      .strip
  end

  PTY::ExecutionResult.new(output: clean_output, status: exit_status)
end
