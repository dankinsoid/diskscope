class Dscope < Formula
  desc "Find what is eating your disk space"
  homepage "https://github.com/dankinsoid/diskscope"
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  url "https://github.com/dankinsoid/diskscope/releases/download/v#{version}/dscope-#{version}-macos.tar.gz"

  depends_on macos: :sonoma

  def install
    bin.install "dscope-#{version}/dscope"
    prefix.install "dscope-#{version}/skills"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/dscope --version")
    system bin/"dscope", "scan", testpath, "--json"
  end
end
