# Streams execution chunks interactively in real time down an open session pipeline
def run(command_string : String, &stream_callback : String ->) : PTY::ExecutionResult
  initial_snapshot_size = @output.bytesize
  start_sentinel, end_sentinel = generate_sentinels
  captured_text = ""

  # Phase 1: Setup live real-time routing listener
  activate_live_filter(->(chunk : String) {
    captured_text += chunk
    stream_callback.call(chunk)
  })

  # Phase 2: Dispatch wrapped terminal commands and block until done
  dispatch_sandwich_commands(command_string, start_sentinel, end_sentinel)
  wait_for(end_sentinel)
  deactivate_live_filter

  # Phase 3: Extract clean results out of the sandboxed boundaries
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

# -------------------------------------------------------------
# The 4 Easy-To-Remember Private Helpers
# -------------------------------------------------------------

# Helper A: Generates the boundary walls
include GenerateSentinels

# Helper B: Binds the lossless real-time stream pipe hooks
include LiveFilter

# Helper C: Transmits the text sandwich straight down the interactive line
include DispatchSandwichCommands

# Helper D:
include HarvestExecutionBlock
