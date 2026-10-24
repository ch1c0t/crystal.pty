private def harvest_execution_block(
  snapshot_index : Int32,
  command_string : String,
  start_sentinel : String,
  end_sentinel : String,
  captured_text : String
) : PTY::ExecutionResult
  # 1. Audit the entry metrics and the raw incoming text data payload size
  transcript = output[snapshot_index..-1]
  
  debug_log("harvest_execution_block :: Invoked", {
    snapshot_index: snapshot_index,
    transcript_bytesize: transcript.bytesize,
    captured_text_bytesize: captured_text.bytesize
  })

  # 2. Extract exit state code using our reverse-index scanner
  exit_status = extract_status_code(transcript, end_sentinel)

  # 3. Clean the transcript block out of the sentinel sandboxed buffer
  clean_output = ""
  if raw_payload = isolate_sandboxed_payload(transcript, start_sentinel, end_sentinel)
    clean_output = strip_terminal_noise(raw_payload)
  end

  # 4. Fallback safeguard check if line formatting caused anomalies
  if clean_output.empty? && !captured_text.empty?
    debug_log("harvest_execution_block :: Captured Text Fallback", "")
    clean_output = strip_terminal_noise(captured_text)
  end

  # 5. Final output check confirming what the assertion block will receive
  debug_log("harvest_execution_block :: Completed Evaluation", {
    final_cleaned_output: clean_output,
    final_exit_status: exit_status
  })

  PTY::ExecutionResult.new(output: clean_output, status: exit_status)
end

include ExtractStatusCode
include IsolateSandboxedPayload
include StripTerminalNoise
