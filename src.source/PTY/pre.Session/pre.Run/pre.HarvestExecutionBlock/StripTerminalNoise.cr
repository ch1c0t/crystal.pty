# Strips control characters, shell prompts, and trailing carrier returns
private def strip_terminal_noise(text : String) : String
  # Strip TTY spacing variables, shell markers ($), and root symbols (#)
  text.strip("\r\n$ #%")
end
