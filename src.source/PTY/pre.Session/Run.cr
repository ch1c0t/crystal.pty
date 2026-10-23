# Streams execution chunks interactively in real time down an open session pipeline
def run(command_string : String, &stream_callback : String ->) : PTY::ExecutionResult
  start_sentinel, end_sentinel = generate_sentinels
  captured_text = ""

  initial_snapshot_size = add_queue do |run_queue|
    dispatch_sandwich_commands(command_string, start_sentinel, end_sentinel)

    loop do
      message = run_queue.pop
      case message
      in String
        captured_text += message
        stream_callback.call(message)
        break if captured_text.includes?(end_sentinel)
      in Symbol
        case message
        when :session_closed
          break
        end
      end
    end
  end


  # Extract clean results out of the sandboxed boundaries
  harvest_execution_block(
    initial_snapshot_size, 
    command_string, 
    start_sentinel, 
    end_sentinel, 
    captured_text
  )
end

# Overload matching block-less execution requests
def run(command_string : String) : PTY::ExecutionResult
  run(command_string) { |_chunk| }
end

include GenerateSentinels
include DispatchSandwichCommands
include HarvestExecutionBlock
