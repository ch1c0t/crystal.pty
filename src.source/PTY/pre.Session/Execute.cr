# Backward compatibility adapter for one-shot block commands (Command class)
def execute(command_string : String, stream_callback : (String -> Nil)?)
  if callback = stream_callback
    run(command_string) { |chunk| callback.call(chunk) }
  else
    run(command_string)
  end
end
