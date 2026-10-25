require "spec"
require "../../src/pty"

describe PTY::Session do
  it "accepts an executable path string" do
    session = PTY::Session.new("/bin/sh")

    session.started?.should be_false
  end

  it "accepts a known shell symbol" do
    session = PTY::Session.new(:sh)

    session.started?.should be_false
  end

  it "rejects shell command strings during construction" do
    expect_raises(ArgumentError) do
      PTY::Session.new("/bin/sh -c 'sleep 30'")
    end
  end

  it "rejects unknown shell symbols" do
    expect_raises(ArgumentError) do
      PTY::Session.new(:unknown_shell)
    end
  end

  it "rejects paths that do not resolve to an executable" do
    expect_raises(ArgumentError) do
      PTY::Session.new("/definitely/not/a/shell")
    end
  end

  it "validates shells in the dimensions-keyword constructor too" do
    expect_raises(ArgumentError) do
      PTY::Session.new(rows: 40, columns: 120, shell: "/bin/sh -c 'sleep 30'")
    end
  end
end
