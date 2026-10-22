private def harvest_execution_block(
  snapshot_index : Int32, 
  command_string : String, 
  start_sentinel : String, 
  end_sentinel : String, 
  captured_text : String
) : PTY::ExecutionResult

  command_transcript = @output[snapshot_index..-1]
  exit_status = 0

  # 1. Harvest the exact numeric exit status code cleanly from the end token
  if match = command_transcript.match(/#{end_sentinel}__(\d+)__/)
    exit_status = match[1].to_i
  else
    if !@reader_active && (proc = @process)
      exit_status = proc.wait.exit_code rescue 0
    end
  end

  # 2. LINE-BY-LINE BLOCK HARVESTER (100% Immune to out-of-order buffering)
  # Split the transcript into component lines and filter out any infrastructure rows.
  clean_lines = [] of String
  
  command_transcript.each_line do |line|
    # Skip infrastructure echoes, sentinel keywords, and standalone trailing shell prompts
    next if line.includes?(start_sentinel)
    next if line.includes?(end_sentinel)
    next if line.includes?("echo START_MARK")
    next if line.includes?("echo END_MARK")
    next if line.strip == "$" || line.strip == "%"
    
    # Strip out direct input command echoes cleanly
    clean_line = line.gsub(/#{Regex.escape(command_string)}/, "").strip

    # Strip common leading shell prompt decorations ($ , % , # )
    # if they are attached to the front of the output line text
    clean_line = clean_line.sub(/^[\$\%\#]\s*/, "").strip

    clean_lines << clean_line unless clean_line.empty?
  end

  clean_output = clean_lines.join("\n").strip

  # Fallback to the raw captured text if the line parser yields an empty block
  if clean_output.empty? && !captured_text.empty?
    clean_output = captured_text
      .gsub(/#{Regex.escape(command_string)}\r?\n/, "")
      .gsub(/echo START_MARK_.+?\r?\n/, "")
      .gsub(/echo END_MARK_.+?\r?\n/, "")
      .strip
  end

  PTY::ExecutionResult.new(output: clean_output, status: exit_status)
end
