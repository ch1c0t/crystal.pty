require "./srun/*"

VERSION = "0.1.0"

case ARGV.size
when 1
  case ARGV[0]
  when "-v", "version", "--version"
    puts VERSION
    exit
  when "-h", "help", "--help"
    print_help
    exit
  end
end

require "file_utils"
require "option_parser"

module SRun
  DEFAULT_TIMEOUT_SECONDS = 30
  KILL_GRACE_SECONDS = 2

  record SpecResult,
    spec : String,
    outcome : String,
    exit_code : Int32?,
    elapsed_seconds : Float64,
    log_path : String,
    excerpt : String

  class Runner
    def initialize(@timeout_seconds : Int32)
      raise ArgumentError.new("timeout must be positive") unless @timeout_seconds > 0
    end

    def run : Int32
      started_at = Time.local
      monotonic_start = Time.monotonic
      directory_name = File.basename(Dir.current)
      directory_name = "root" if directory_name.empty?
      timestamp = started_at.to_s("%Y%m%d_%H%M%S")
      base_root_dir = File.join(Dir.current, "#{directory_name}.srun.#{started_at.to_unix}_#{timestamp}")
      root_dir = base_root_dir
      suffix = 2
      loop do
        begin
          Dir.mkdir(root_dir)
          break
        rescue ex : File::AlreadyExistsError
          root_dir = "#{base_root_dir}.#{suffix}"
          suffix += 1
        end
      end

      passing_dir = File.join(root_dir, "passing")
      failing_dir = File.join(root_dir, "failing")
      report_path = File.join(root_dir, "report.txt")

      FileUtils.mkdir_p(passing_dir)
      FileUtils.mkdir_p(failing_dir)

      specs = Dir.glob("spec/**/*_spec.cr").sort
      results = [] of SpecResult
      write_report(report_path, root_dir, started_at, @timeout_seconds, specs, results, 0.0)

      if specs.empty?
        STDERR.puts "srun: no spec files found matching spec/**/*_spec.cr"
        return 1
      end

      specs.each_with_index do |spec, index|
        puts "[#{index + 1}/#{specs.size}] Running #{spec} (timeout: #{@timeout_seconds}s)"
        result = run_spec(spec, @timeout_seconds, passing_dir, failing_dir)
        results << result

        puts "  #{result.outcome}: #{spec} (#{result.elapsed_seconds.round(2)}s)"
        elapsed = (Time.monotonic - monotonic_start).total_seconds
        write_report(report_path, root_dir, started_at, @timeout_seconds, specs, results, elapsed)
      end

      passed = results.count { |result| result.outcome == "PASS" }
      failed = results.size - passed
      elapsed = (Time.monotonic - monotonic_start).total_seconds

      puts
      puts "srun finished: #{passed} passed, #{failed} failed, #{elapsed.round(2)}s"
      puts "Report: #{report_path}"
      puts "Logs:   #{root_dir}"

      failed == 0 ? 0 : 1
    end

    private def run_spec(
      spec : String,
      timeout_seconds : Int32,
      passing_dir : String,
      failing_dir : String
    ) : SpecResult
      filename = "#{spec.gsub("/", "__")}.log"
      failing_path = File.join(failing_dir, filename)
      started = Time.monotonic
      exit_code = nil.as(Int32?)

      # GNU timeout runs each spec in its own process group so a timeout can
      # stop the spec runner and subprocesses it started, not just this wrapper.
      File.open(failing_path, "w") do |log|
        begin
          status = Process.run(
            "timeout",
            [
              "--verbose",
              "--signal=TERM",
              "--kill-after=#{KILL_GRACE_SECONDS}s",
              "#{timeout_seconds}s",
              "crystal",
              "spec",
              spec,
            ],
            output: log,
            error: log
          )
          exit_code = status.exit_code
          log.flush
        rescue ex
          log.puts
          log.puts("srun could not launch crystal spec: #{ex.class}: #{ex.message}")
          log.flush
        end
      end

      elapsed = (Time.monotonic - started).total_seconds
      output = File.read(failing_path)
      timed_out = output.includes?("timeout: sending signal")
      outcome = if timed_out
                  "TIMEOUT"
                elsif exit_code == 0
                  "PASS"
                elsif exit_code.nil?
                  "RUNNER ERROR"
                else
                  "FAIL"
                end

      if outcome == "PASS"
        File.rename(failing_path, File.join(passing_dir, filename))
        log_path = File.join("passing", filename)
        excerpt = ""
      else
        log_path = File.join("failing", filename)
        excerpt = output.lines.map(&.rstrip).last(12).join("\n")
      end

      SpecResult.new(spec, outcome, exit_code, elapsed, log_path, excerpt)
    end

    private def write_report(
      report_path : String,
      root_dir : String,
      started_at : Time,
      timeout_seconds : Int32,
      specs : Array(String),
      results : Array(SpecResult),
      elapsed_seconds : Float64
    ) : Nil
      passed = results.count { |result| result.outcome == "PASS" }
      failed = results.size - passed
      completed_specs = results.map(&.spec)
      lines = [] of String
      lines << "srun report"
      lines << "==========="
      lines << "Run directory: #{root_dir}"
      lines << "Working directory: #{Dir.current}"
      lines << "Started at: #{started_at.to_s("%Y-%m-%d %H:%M:%S")} (Unix time #{started_at.to_unix})"
      lines << "Spec glob: spec/**/*_spec.cr"
      lines << "Per-spec timeout: #{timeout_seconds}s (TERM, then KILL after #{KILL_GRACE_SECONDS}s)"
      lines << "Discovered: #{specs.size}"
      lines << "Completed: #{results.size}/#{specs.size}"
      lines << "Passed: #{passed}"
      lines << "Failed: #{failed}"
      lines << "Elapsed: #{elapsed_seconds.round(2)}s"
      lines << ""
      lines << "Results"
      lines << "-------"

      if specs.empty?
        lines << "Note: no spec files found matching spec/**/*_spec.cr."
      elsif results.empty?
        lines << "(No specs completed yet.)"
      else
        results.each do |result|
          lines << "#{result.outcome}: #{result.spec}"
          lines << "  elapsed: #{result.elapsed_seconds.round(2)}s"
          lines << "  exit code: #{result.exit_code || "unavailable"}"
          if result.outcome == "TIMEOUT"
            lines << "  reason: exceeded the #{timeout_seconds}s timeout; timeout sent TERM and escalated to KILL if needed."
          elsif result.outcome == "FAIL"
            lines << "  reason: crystal spec exited unsuccessfully (exit code #{result.exit_code})."
          elsif result.outcome == "RUNNER ERROR"
            lines << "  reason: srun could not start the timeout/crystal spec process."
          end
          lines << "  full output: #{File.join(root_dir, result.log_path)}"

          unless result.excerpt.empty?
            lines << "  last output lines:"
            result.excerpt.lines.each do |line|
              lines << "    #{line}"
            end
          end
          lines << ""
        end
      end

      pending = specs.reject { |spec| completed_specs.includes?(spec) }
      unless pending.empty?
        lines << "Not yet run"
        lines << "-----------"
        pending.each { |spec| lines << spec }
      end

      File.write(report_path, lines.join("\n") + "\n")
    end
  end
end

timeout_seconds = SRun::DEFAULT_TIMEOUT_SECONDS
if env_timeout = ENV["SRUN_TIMEOUT"]?
  parsed_timeout = env_timeout.to_i?
  unless parsed_timeout && parsed_timeout > 0
    STDERR.puts "srun: SRUN_TIMEOUT must be a positive integer number of seconds"
    exit 2
  end
  timeout_seconds = parsed_timeout
end

OptionParser.parse do |parser|
  parser.banner = "Usage: srun [--timeout SECONDS]"
  parser.on("-t SECONDS", "--timeout=SECONDS", "Timeout for each spec (default: #{timeout_seconds}s)") do |value|
    parsed_timeout = value.to_i?
    unless parsed_timeout && parsed_timeout > 0
      STDERR.puts "srun: timeout must be a positive integer number of seconds"
      exit 2
    end
    timeout_seconds = parsed_timeout
  end
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
end

unless ARGV.empty?
  STDERR.puts "srun: unexpected arguments: #{ARGV.join(" ")}"
  STDERR.puts "Try 'srun --help' for usage."
  exit 2
end

exit SRun::Runner.new(timeout_seconds).run
