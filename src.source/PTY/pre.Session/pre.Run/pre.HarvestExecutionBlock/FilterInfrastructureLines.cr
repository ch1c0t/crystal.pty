private def filter_infrastructure_lines(
  transcript : String, 
  command_string : String, 
  start_sentinel : String, 
  end_sentinel : String
) : String
  clean_lines = [] of String
  
  transcript.each_line do |line|
    trimmed_line = line.strip

    # 1. Skip core infrastructure sentinel rows cleanly using explicit words
    next if trimmed_line.includes?("START_MARK")
    next if trimmed_line.includes?("END_MARK")
    
    # 2. FIXED: Catch split trailing sentinel fragments (like "738_730__$?__") 
    # by checking if the row ends with the unique sentinel indicator sequence
    next if trimmed_line.ends_with?("__$?__")
    next if trimmed_line.includes?("__") && trimmed_line.ends_with?("__")

    # 3. Clean out direct input command echoes
    clean_line = line.gsub(/#{Regex.escape(command_string)}/, "").strip
    
    # 4. Strip leading prompt indicators cleanly without a complex regex matcher
    if clean_line.starts_with?('$') || clean_line.starts_with?('%') || clean_line.starts_with?('#')
      clean_line = clean_line[1..-1].strip
    end
    
    clean_lines << clean_line unless clean_line.empty?
  end

  clean_lines.join("\n").strip
end
