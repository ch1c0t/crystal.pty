# Streams execution chunks interactively in real time down an open session pipeline
def run(command_string : String, &stream_callback : String ->) : PTY::ExecutionResult
  captured_text = ""
  initial_snapshot_size = @output.bytesize
  sentinel = "CMD_MARK_#{Random.rand(100000..999999)}"

  @mutex.synchronize do
    @active_run_callback = ->(chunk : String) {
      unless chunk.includes?(sentinel)
        captured_text += chunk
        stream_callback.call(chunk)
      end
    }
  end

  write("#{command_string}\n")
  write("echo #{sentinel}__$?__\n")

  wait_for(sentinel)

  @mutex.synchronize do
    @active_run_callback = nil
  end

  command_transcript = @output[initial_snapshot_size..-1]
  exit_status = 0
  if match = command_transcript.match(/#{sentinel}__(\d+)__/)
    exit_status = match[1].to_i
  end

  clean_output = captured_text
    .gsub(/#{command_string}\r?\n/, "")
    .gsub(/echo #{sentinel}__\$\?__\r?\n/, "")
    .strip

  PTY::ExecutionResult.new(output: clean_output, status: exit_status)
end

def run(command_string : String) : PTY::ExecutionResult
  run(command_string) { |_chunk| }
end
