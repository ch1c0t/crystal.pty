def alive? : Bool
  if process = @process
    !process.exists? || process.terminated? ? false : true
  else
    false
  end
end

# Returns whether the pseudo-terminal descriptors have been booted
def started? : Bool
  @started.get
end
