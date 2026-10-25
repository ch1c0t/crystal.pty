private def validated_shell(shell : Nil) : String
  validated_shell("/bin/sh")
end

private def validated_shell(shell : Symbol) : String
  case shell
  when :sh, :bash, :zsh, :fish, :dash, :ksh, :csh, :tcsh
    shell.to_s
  else
    raise ArgumentError.new("Unknown PTY shell symbol: #{shell.inspect}")
  end
end

private def validated_shell(shell : String) : String
  candidate = shell

  process_env = ENV.to_h
  if custom_env = @env
    process_env.merge!(custom_env)
  end
  search_path = process_env["PATH"]? || "/usr/bin:/bin"
  unless Process.find_executable(candidate, search_path)
    raise ArgumentError.new("PTY shell must resolve to an executable path; got #{shell.inspect}")
  end

  candidate
end
