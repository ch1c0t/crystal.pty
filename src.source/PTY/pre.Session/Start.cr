# STRICTLY starts a vanilla interactive shell session without inputs or blocks
def start : self
  debug_log("Session Boot Sequence Triggered", {
    target_shell: @shell,
    dimensions: "#{@rows} rows x #{@columns} columns",
    working_dir: @cwd,
    custom_env: @env
  })

  # Guard against booting an already running process
  if @started.swap(true)
    debug_log("Session Start Aborted - Process is Already Running", "")
    return self
  end

  # Phase 1: Allocate system virtual descriptors
  master_fd, slave_fd = allocate_pty
  update_kernel_terminal_dimensions_by_fd(master_fd)

  # Phase 2: Pre-Flight Staging (Run on the mainland parent heap)
  env_payload, target_shell, target_cwd = stage_pre_flight_primitives

  # Phase 3: The Process Split Boundary
  pid = PTY::C.fork
  if pid < 0
    raise "Error: OS process fork failed."
  elsif pid == 0
    # INSIDE CHILD
    execute_child_sandbox(slave_fd, env_payload, target_cwd, target_shell)
  else
    # INSIDE PARENT
    initialize_parent_proxy(pid, slave_fd, master_fd)
    debug_log("Before #wait_for in #start: Entering Initial Shell Settlement Sync Guard", {
      waiting_for_token: "$ ",
      current_history_size: output.bytesize
    })
    wait_for("$ ") rescue nil
  end

  debug_log("Session Boot Sequence Complete - Ready for Pasted Script Inputs", {
    final_history_snapshot: output
  })

  self
end

include AllocatePTY
include UpdateKernelTerminalDimensions
include StagePreFlightPrimitives
include ExecuteChildSandbox
include InitializeParentProxy
