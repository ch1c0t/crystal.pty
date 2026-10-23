# Isolates the captured text and extracts the exit status safely
private def harvest_execution_block(
  snapshot_index : Int32, 
  command_string : String, 
  start_sentinel : String, 
  end_sentinel : String, 
  captured_text : String
) : PTY::ExecutionResult

  command_transcript = output[snapshot_index..-1]

  # Step 1: Extract status
  exit_status = extract_exit_code(command_transcript, end_sentinel)

  # Step 2: Line-by-line infrastructure filtering
  clean_output = filter_infrastructure_lines(command_transcript, command_string, start_sentinel, end_sentinel)

  # Step 3: Fallback verification if the line buffer yielded an empty block
  if clean_output.empty? && !captured_text.empty?
    clean_output = fallback_clean_text(captured_text, command_string, start_sentinel, end_sentinel)
  end

  PTY::ExecutionResult.new(output: clean_output, status: exit_status)
end

include ExtractExitCode
include FilterInfrastructureLines
include FallbackCleanText
