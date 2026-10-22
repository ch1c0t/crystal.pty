# Helper 3: Secondary cleanup filter block targeting raw real-time captured buffers
private def fallback_clean_text(
  captured_text : String, 
  command_string : String, 
  start_sentinel : String, 
  end_sentinel : String
) : String
  captured_text
    .gsub(/#{Regex.escape(command_string)}\r?\n/, "")
    .gsub(/echo START_MARK_.+?\r?\n/, "")
    .gsub(/echo #{end_sentinel}__\$\?__\r?\n/, "")
    .sub(/^[\$\%\#]\s*/, "")
    .strip
end
