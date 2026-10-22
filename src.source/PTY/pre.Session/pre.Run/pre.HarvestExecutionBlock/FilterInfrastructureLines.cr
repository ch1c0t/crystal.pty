# Helper 2: Strips markers, echoes, and prompt decorations line-by-line
private def filter_infrastructure_lines(
  transcript : String, 
  command_string : String, 
  start_sentinel : String, 
  end_sentinel : String
) : String
  clean_lines = [] of String
  
  transcript.each_line do |line|
    next if line.includes?(start_sentinel)
    next if line.includes?(end_sentinel)
    next if line.includes?("echo START_MARK")
    next if line.includes?("echo END_MARK")
    
    # Clean out direct command echo inputs
    clean_line = line.gsub(/#{Regex.escape(command_string)}/, "").strip
    
    # Strip leading interactive prompt symbols ($ , % , # ) safely
    clean_line = clean_line.sub(/^[\$\%\#]\s*/, "").strip
    
    clean_lines << clean_line unless clean_line.empty?
  end

  clean_lines.join("\n").strip
end
