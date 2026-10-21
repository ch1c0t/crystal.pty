# Resizes the ongoing active subshell terminal window on-the-fly
def resize(rows : Int32, columns : Int32)
  @rows = rows
  @columns = columns
  update_kernel_terminal_dimensions
end
