require "spec"
require "random"
require "../../../src/pty"

describe PTY::Session do
  # Keep the descendant in the shell's process group and make it survive
  # SIGHUP/SIGTERM, so terminating only the shell cannot satisfy this test.
  it "terminates the process group, including a surviving descendant" do
    suffix = "#{Process.pid}-#{Random.rand(1_000_000_000)}"
    pid_file = "/tmp/crystal-pty-terminate-#{suffix}.pid"
    pgid_file = "/tmp/crystal-pty-terminate-#{suffix}.pgid"
    heartbeat_file = "/tmp/crystal-pty-terminate-#{suffix}.heartbeat"
    session = PTY::Session.new("/bin/sh")
    termination_verified = false

    begin
      session.start
      session.write("set +m\n")
      session.write(
        "/bin/sh -c 'echo $$ > #{pid_file}; echo $PPID > #{pgid_file}; " +
        "trap \"\" TERM HUP; while :; do echo tick >> #{heartbeat_file}; sleep 0.02; done' &\n"
      )

      # Wait for the background shell to publish its PID and process group.
      started_at = Time.instant
      until File.exists?(pgid_file)
        (Time.instant - started_at).should be < 3.seconds
        sleep 10.milliseconds
      end

      started_at = Time.instant
      until File.exists?(heartbeat_file) && !File.read(heartbeat_file).empty?
        (Time.instant - started_at).should be < 3.seconds
        sleep 10.milliseconds
      end

      started_at = Time.instant
      session.terminate
      (Time.instant - started_at).should be < 3.seconds
      session.alive?.should be_false

      # A dead shell is insufficient: the descendant must stop producing output.
      settled_size = File.read(heartbeat_file).bytesize
      sleep 100.milliseconds
      File.read(heartbeat_file).bytesize.should eq(settled_size)
      termination_verified = true
    ensure
      session.terminate

      # Keep a failing regression test from leaving its deliberately stubborn
      # child running on the test host.
      if !termination_verified && File.exists?(pgid_file)
        pgid = File.read(pgid_file).strip
        Process.run("/bin/kill", ["-KILL", "--", "-#{pgid}"], output: Process::Redirect::Close, error: Process::Redirect::Close) rescue nil
      end

      {pid_file, pgid_file, heartbeat_file}.each do |path|
        File.delete(path) if File.exists?(path)
      end
    end
  end
end
