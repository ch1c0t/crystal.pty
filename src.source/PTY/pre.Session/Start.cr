# STRICTLY starts a vanilla interactive shell session without inputs or blocks
def start : self
  return self if started?

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
  end
  self
end

include AllocatePTY
include UpdateKernelTerminalDimensions
include StagePreFlightPrimitives
include ExecuteChildSandbox
include InitializeParentProxy
