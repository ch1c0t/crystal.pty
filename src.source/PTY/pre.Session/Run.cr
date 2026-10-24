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
        debug_log("run :: String Message", {
          message_chunk: message,
          total_accumulated_bytes: captured_text.bytesize
        })

        captured_text += message
        stream_callback.call(message)

        if command_sandwich_complete?(captured_text, start_sentinel, end_sentinel)
          break
        end
      in Symbol
        debug_log("run :: Control Message", {
          event_token: message
        })

        case message
        when :session_closed
          break
        when :stream_idle
          # Input echo can contain both sentinels before the command has finished.
          # Only stop when the end marker has an evaluated numeric exit status.
          if command_sandwich_complete?(captured_text, start_sentinel, end_sentinel)
            break
          end
        when :subscriber_detached, :command_timeout
          break
        end
      end
    end
  end

  harvest_execution_block(
    initial_snapshot_size,
    command_string,
    start_sentinel,
    end_sentinel,
    captured_text
  )
end

def run(command_string : String) : PTY::ExecutionResult
  run(command_string) { |_chunk| }
end

include GenerateSentinels
include DispatchSandwichCommands
include CommandSandwichComplete
include HarvestExecutionBlock
